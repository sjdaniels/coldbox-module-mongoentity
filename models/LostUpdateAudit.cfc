/**
 * Phase 0 lost-update auditing: measures how often ActiveEntity.save() silently reverts another
 * request's write, WITHOUT changing any write behaviour.
 *
 * save() replaces the whole document from the entity's in-memory snapshot, so a field another
 * request changed since this instance was loaded is written back to the value this instance loaded.
 * No error, no event, nothing in the document to show it happened.
 *
 * The detection is exact rather than heuristic. populateFromDoc() keeps the document as loaded, so
 * at save time three states are distinguishable per field:
 *
 *   loaded == about-to-write   ->  this request did not change the field
 *   stored != loaded           ->  somebody else did change it
 *   both true                  ->  this write destroys their change. That is a lost update.
 *
 * A field this request genuinely changed is not reported, however stale it looks, because that is
 * an ordinary write.
 *
 * Costs one extra read per save of an audited collection, so auditing is opt-in per collection and
 * meant to be switched off once the numbers are in. Nothing here may ever throw into a write path -
 * every entry point swallows its own errors.
 *
 * Configure in the host app via moduleSettings.mongoentity.lostUpdateAudit - see ModuleConfig.cfc.
 */
component singleton {

	property name="settings" inject="coldbox:moduleSettings:mongoentity";
	property name="MongoDB" inject="id";

	// Hot-path gate. populateFromDoc() runs for every document of every list, so the check it makes
	// has to be a bare application-scope lookup: the key exists only while auditing is on, and holds
	// the audited collection names. Anything DI-shaped here would be paid per hydrated document.
	variables.GATE_KEY = "mongoentity_auditcollections";

	public LostUpdateAudit function init(){
		return this;
	}

	public LostUpdateAudit function onDIComplete(){
		configure();
		return this;
	}

	/**
	 * Publishes (or clears) the hot-path gate from the module settings. Safe to call at runtime to
	 * turn auditing on or off without a redeploy.
	 */
	public LostUpdateAudit function configure(){
		try {
			var cfg = variables.settings.lostUpdateAudit ?: {};

			if (!(cfg.enabled ?: false) || !(cfg.collections ?: {}).count()) {
				structDelete( application, variables.GATE_KEY );
				return this;
			}

			// the gate holds the sample rate per collection, so populateFromDoc() can decide with a
			// scope lookup and at most one rand() - no settings read on the hydration path
			var gate = {};
			for (var name in cfg.collections)
				gate[ name ] = cfg.collections[ name ];

			application[ variables.GATE_KEY ] = gate;
			ensureTTL( cfg );
		}
		catch (any e) {
			structDelete( application, variables.GATE_KEY );
			logFailure( "configure", e );
		}

		return this;
	}

	/** Whether the gate is currently published for this collection. */
	public boolean function isAuditing( string collection="" ){
		return structKeyExists( application, variables.GATE_KEY )
			&& structKeyExists( application[ variables.GATE_KEY ], arguments.collection );
	}

	/**
	 * The log is written from inside save(), and if lost updates turn out to be common it grows as
	 * fast as they happen. A TTL keeps a measurement window from becoming a storage problem.
	 */
	private void function ensureTTL( required struct cfg ){
		try {
			var days = arguments.cfg.ttlDays ?: 0;
			if (!days)
				return;

			MongoDB.getCollection( arguments.cfg.logCollection ?: "mongoentity_lostupdates" )
				.createIndex( { "dateCreated":1 }, { "name":"ttl_dateCreated", "expireAfterSeconds":javacast( "int", days * 86400 ) } );
		}
		catch (any e) {
			// an existing index with different options throws; not worth failing configure() over
			logFailure( "ensureTTL", e );
		}
	}

	/**
	 * Called from save() with the document about to be written and the document as loaded. Records a
	 * finding per field this write would silently revert.
	 */
	public void function inspect(
		 required string collection
		,required struct doc
		,required struct snapshot
		,string entity=""
	){
		try {
			if (!isAuditing( arguments.collection ))
				return;

			var cfg    = variables.settings.lostUpdateAudit ?: {};
			var ignore = cfg.ignoreFields ?: [];
			var id     = arguments.doc[ "_id" ] ?: nullValue();

			if (isnull( id ))
				return;

			var stored = MongoDB.getCollection( arguments.collection ).findOne( { "_id":id } );
			// nothing stored means this is an insert - there is no concurrent write to lose
			if (isnull( stored ))
				return;

			var findings = [];

			// fields we are about to write
			for (var key in arguments.doc) {
				if (key == "_id" || ignore.findNoCase( key ))
					continue;

				// did THIS request change the field? then writing it is intentional, whatever the
				// stored value looks like
				if (!structKeyExists( arguments.snapshot, key ) || differs( arguments.doc[ key ], arguments.snapshot[ key ] ))
					continue;

				if (!structKeyExists( stored, key )) {
					// somebody removed it and we are about to put it back
					findings.append( finding( key, "revive", arguments.snapshot[ key ], nullValue(), arguments.doc[ key ], cfg ) );
					continue;
				}

				if (differs( stored[ key ], arguments.doc[ key ] ))
					findings.append( finding( key, "overwrite", arguments.snapshot[ key ], stored[ key ], arguments.doc[ key ], cfg ) );
			}

			// fields we are about to drop. getMemento() omits empty values and undeclared properties,
			// and a whole-document replace turns omission into deletion - so these disappear too.
			for (var key in stored) {
				if (key == "_id" || structKeyExists( arguments.doc, key ) || ignore.findNoCase( key ))
					continue;

				if (!structKeyExists( arguments.snapshot, key ))
					findings.append( finding( key, "delete-of-new-field", nullValue(), stored[ key ], nullValue(), cfg ) );
				else if (differs( stored[ key ], arguments.snapshot[ key ] ))
					findings.append( finding( key, "delete-of-changed-field", arguments.snapshot[ key ], stored[ key ], nullValue(), cfg ) );
			}

			if (findings.len())
				record( arguments.collection, arguments.entity, id, findings, cfg );
		}
		catch (any e) {
			logFailure( "inspect", e );
		}
	}

	/*********************************** INTERNALS ***********************************/

	private struct function finding(
		 required string field
		,required string kind
		,any loaded
		,any current
		,any writing
		,required struct cfg
	){
		var result = { "field":arguments.field, "kind":arguments.kind };

		if (!isnull( arguments.loaded ))	result[ "loaded" ]	= describe( arguments.loaded, arguments.cfg );
		if (!isnull( arguments.current ))	result[ "current" ]	= describe( arguments.current, arguments.cfg );
		if (!isnull( arguments.writing ))	result[ "writing" ]	= describe( arguments.writing, arguments.cfg );

		return result;
	}

	/**
	 * Writes one document per detection. The request path and call stack are the point of the
	 * exercise: they name the writer that is losing the other request's change, which is the one
	 * thing the member document itself can never tell you afterwards.
	 */
	private void function record(
		 required string collection
		,required string entity
		,required any id
		,required array findings
		,required struct cfg
	){
		var doc = {
			 "dateCreated"	: now()
			,"collection"	: arguments.collection
			,"entity"		: arguments.entity
			,"docID"		: isSimpleValue( arguments.id ) ? arguments.id : arguments.id.toString()
			,"fields"		: arguments.findings.map( ( f ) => f.field )
			,"findings"		: arguments.findings
			,"path"			: cgi.path_info ?: ""
			,"query"		: cgi.query_string ?: ""
			,"stack"		: stack()
		};

		MongoDB.getCollection( arguments.cfg.logCollection ?: "mongoentity_lostupdates" ).save( doc );
	}

	/**
	 * Trimmed call stack - enough to name the save() call site without storing a novel.
	 *
	 * The auditor's own frames and ActiveEntity's are dropped because they are on every single entry
	 * and say nothing; what is wanted is the application code that called save(). Matched on the
	 * filename rather than a substring of the path, so a caller named e.g. LostUpdateAuditSpec is not
	 * silently filtered out along with LostUpdateAudit itself.
	 */
	private array function stack(){
		try {
			var skip = [ "LostUpdateAudit.cfc", "ActiveEntity.cfc" ];
			var out  = [];

			for (var f in callStackGet()) {
				var tpl = f.template ?: "";

				if (skip.findNoCase( getFileFromPath( tpl ) ))
					continue;

				out.append( "#tpl#:#f.lineNumber ?: 0#" );

				if (out.len() >= 14)
					break;
			}

			return out;
		}
		catch (any e) {
			return [];
		}
	}

	/** Serialised and length-capped, so one fat entitlements struct can't bloat the log. */
	private string function describe( required any value, required struct cfg ){
		var max = arguments.cfg.maxValueChars ?: 500;
		var out = "";

		try {
			out = isSimpleValue( arguments.value ) ? arguments.value.toString() : serializeJSON( arguments.value );
		}
		catch (any e) {
			out = "[unserialisable #e.message#]";
		}

		return out.len() > max ? out.left( max ) & "…[#out.len()# chars]" : out;
	}

	/**
	 * Deep inequality. Deliberately not serializeJSON on both sides and compared as strings - struct
	 * key order is not guaranteed, which would manufacture findings out of identical values.
	 */
	private boolean function differs( any a, any b ){
		if (isnull( arguments.a ) || isnull( arguments.b ))
			return !(isnull( arguments.a ) && isnull( arguments.b ));

		if (isSimpleValue( arguments.a ) && isSimpleValue( arguments.b ))
			return arguments.a.toString() != arguments.b.toString();

		if (isArray( arguments.a ) && isArray( arguments.b )) {
			if (arguments.a.len() != arguments.b.len())
				return true;

			for (var i = 1; i <= arguments.a.len(); i++)
				if (differs( arguments.a[ i ] ?: nullValue(), arguments.b[ i ] ?: nullValue() ))
					return true;

			return false;
		}

		if (isStruct( arguments.a ) && isStruct( arguments.b )) {
			// no key-count shortcut: the two loops below already cover a key missing from either side
			for (var key in arguments.a) {
				if (!structKeyExists( arguments.b, key ))
					return true;
				if (differs( arguments.a[ key ] ?: nullValue(), arguments.b[ key ] ?: nullValue() ))
					return true;
			}

			for (var key in arguments.b)
				if (!structKeyExists( arguments.a, key ))
					return true;

			return false;
		}

		// mixed or opaque types (ObjectId, Java objects): fall back to string form
		try {
			return arguments.a.toString() != arguments.b.toString();
		}
		catch (any e) {
			return true;
		}
	}

	private void function logFailure( required string where, required any e ){
		try {
			writelog( file:"mongoentity", text:"LostUpdateAudit.#arguments.where# failed: #arguments.e.message# #arguments.e.detail ?: ''#" );
		}
		catch (any ignored) {}
	}
}
