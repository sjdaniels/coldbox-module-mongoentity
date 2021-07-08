/**
*
* @author Sean Daniels 
* @description Base class for MongoDB-backed Active Entity
*
*/
component output="false" accessors="true"  {

	property metadata name="entityName" type="string" persist="false";
	property metadata name="databaseName" type="string" persist="false" default="";
	property metadata name="collectionName" type="string" persist="false";
	property metadata name="collectionIndexes" type="array" persist="false";
	property metadata name="entityProperties" type="struct" persist="false";

	function getLogBox() provider="logbox" {}
	function getWireBox() provider="wirebox" {}
	function getMongoDB() provider="id:MongoDB" {}
	function getMongoHelpers() provider="Utils@mongoentity" {}
	function getTimer() provider="timer@cbdebugger" {}

	public ActiveEntity function init(){
		var md = getMetadata( this );

		// find entity name on md?
		if( structKeyExists(md,"entityName") ){
			setEntityName(md.entityName);
		}
		// else default to entity CFC name
		else{
			setEntityName(listLast( md.name, "." ));
		}

		if ( structkeyexists(md,"collection") ) {
			setCollectionName( md.collection );
		}

		if ( structkeyexists(md,"database") ) {
			setDatabaseName( md.database );
		}

		// set properties with defaults, property list, and set up indexes
		local.collectionIndexes = [];
		local.entityProperties = {};
		for ( var prop in getInheritedProperties( md ) ) {
			local.entityProperties[prop.name] = duplicate(prop);
			if (structkeyexists(prop,"index")) {
				local.index         = structnew();
				local.index.name    = prop.index;
				local.index.unique  = structkeyexists(prop,"unique");
				local.index.sparse  = structkeyexists(prop,"sparse");
				if (structkeyexists(prop,"indexvalue")){
					if (isnumeric(prop.indexvalue))
						prop.indexvalue = javacast("numeric",prop.indexvalue)
					local.index.fields  = [ {"#prop.name#":prop.indexvalue} ];
				} else {
					local.index.fields  = [ prop.name ];
				}
				arrayappend( local.collectionIndexes, local.index );
			}
		}
		
		setEntityProperties(local.entityProperties);
		setCollectionIndexes(local.collectionIndexes);

		// clear properties and reset to default values
		return reset();
	}

	public ActiveEntity function reset() {
		loop collection="#getEntityProperties()#" item="local.prop" index="local.name" {
			
			// skip metadata and injected properties
			if (local.prop.keyExists("metadata") || local.prop.keyExists("inject"))
				continue;

			// clear the value
			structDelete(variables, local.name);
			structDelete(variables, "#local.name#_objectified");

			// set to default value
			if ( local.prop.keyExists("default")) {
				var proptype = local.prop.type ?: "string";
				switch ( proptype ) {
					case "array":
						variables[local.name] = evaluate(local.prop.default);
					break;
					case "struct":
						variables[local.name] = evaluate(local.prop.default);
					break;
					case "date":
						variables[local.name] = evaluate(local.prop.default);
					break;
					case "timestamp":
						variables[local.name] = evaluate(local.prop.default);
						variables["timestampProperty"] = local.name;
					break;
					case "any":
						variables[local.name] = local.prop.default;
					break;
				
					default:
						variables[local.name] = javacast(proptype,local.prop.default);
					break;
				}
			}
		}

		return this;
	}

	public function getVariables(){
		return variables;
	}

	public numeric function getAutoIncrement(string collection=getCollectionName(), numeric seed=1) {
		local.seedcollection = getMongoDB().getCollection("autoincrements");
		
		while (true) {
			local.seed = local.seedcollection.findOne({"collection":arguments.collection});
			if (isnull(local.seed)) // document for this collection does not yet exist, initialize it.
				local.seedcollection.save({ "collection":arguments.collection, "autoincrement":variables.startautoincrement ?: arguments.seed });
			else 
				break;
		}

		var result = local.seed.autoincrement;
		local.seedcollection.update( { "collection":arguments.collection }, { "$inc":{ "autoincrement":1 } })
		return result;
	}

	public any function getCollection() {
		if (isnull(this.getCollectionName()))
			return;

		// returns the native collection using Railo's extension
		if (isnull(variables.mongoDBCollection)) {        	
			if (getDatabaseName()=="")
				variables.mongoDBCollection = getMongoDB().getCollection( getCollectionName() );
			else 
				variables.mongoDBCollection = getMongoDB().getSisterDB( getDatabaseName() ).getCollection( getCollectionName() );
		}
		return variables.mongoDBCollection;
	}

	public any function new(struct properties=structnew()){
		var entity   = _entityNew();
		var key      = "";
		var excludes = "entityName,properties";

		// Properties exists?
		if( NOT structIsEmpty(arguments.properties) ){
			getWirebox().getObjectPopulator().populateFromStruct( entity, arguments.properties );
		}

		return entity;
	}

	public any function get(required any id,boolean returnNew=true) {
		// create a new, empty object
		var result = _entityNew();

		// check if id exists so entityLoad does not throw error
		if( (isSimpleValue(arguments.id) and len(arguments.id)) OR NOT isSimpleValue(arguments.id) ){
			getTimer().start("#getEntityName()#.get( #arguments.id.toString()# )")
				var getDoc = getCollection().findOne({"_id":_mongoID(arguments.id)});
			getTimer().stop("#getEntityName()#.get( #arguments.id.toString()# )")

			// Check if not null, then return it
			if( !isnull(getDoc) ){
				var doc = getDoc;
				populateFromDoc(result,doc);
				return result;
			}
		}

		// Check for return new?
		if( arguments.returnNew ){
			return result;
		}
	}

	public ActiveEntity function load(required any id) {
		this.reset();

		// check if id exists so entityLoad does not throw error
		if( (isSimpleValue(arguments.id) and len(arguments.id)) OR NOT isSimpleValue(arguments.id) ){
			var getDoc = getCollection().findOne({"_id":_mongoID(arguments.id)});

			// Check if not null, then return it
			if( !isnull(getDoc) ){
				populateFromDoc(this,getDoc);
			}
		}

		return this;
	}

	public any function findWhere(struct criteria={}, boolean returnNew=false, string sortorder="") {
		var result = _entityNew();
		local.sort = {};

		// parse sort string into mongo sort struct
		if (!isempty(arguments.sortorder))
			local.sort = getMongoHelpers().sortFormat( arguments.sortorder );

		getTimer().start("#getEntityName()#.findOne( #left(arguments.criteria.toString(),100)# )")
			var doc = getCollection().findOne(arguments.criteria,{},local.sort);
		getTimer().stop("#getEntityName()#.findOne( #left(arguments.criteria.toString(),100)# )")

		if (!isnull(doc)) {
			populateFromDoc(result, doc);
			return result;
		}

		if (arguments.returnNew) return result;

		return;
	}

	public any function list(struct criteria={}, string sortorder="", numeric offset=0, numeric max=0, boolean asQuery=true, numeric limit=0, boolean withRowCount=true, boolean iterator=false, boolean textsort=false) {

		if (arguments.max) arguments.limit = arguments.max;

		// parse sort string into mongo sort struct
		if (!isempty(arguments.sortorder))
			local.sort = getMongoHelpers().sortFormat( arguments.sortorder );

		local.projection = {};
		if (arguments.textsort) {
			local.projection = ["score":{"$meta":"textScore"}]
			local.sort = local.projection;
		}

		getTimer().start("#getEntityName()#.list( #arguments.criteria.toString()# ).sort( #(local.sort?:{}).toString()# )");
			local.cursor = getCollection()
				.find(arguments.criteria, local.projection);

			if (!isnull(local.sort))
				local.cursor.sort(local.sort);

			local.cursor
				.skip(arguments.offset) 
				.limit(arguments.limit); 
		getTimer().stop("#getEntityName()#.list( #arguments.criteria.toString()# ).sort( #(local.sort?:{}).toString()# )");
		
		if (arguments.withRowCount){
			getTimer().start("-- get cursor count")
				this.setRowCount(local.cursor.count());
			getTimer().stop("-- get cursor count")
		}

		// convert cursor into array of objects or query
		if (arguments.asQuery) {
			getTimer().start("-- Converting to query")
				local.result = cursorToQuery(local.cursor);
			getTimer().stop("-- Converting to query")
		} else if (arguments.iterator) {
			getTimer().start("-- Converting to iterator")
				local.result = getIterator(this, local.cursor);
			getTimer().stop("-- Converting to iterator")
		} else {
			getTimer().start("-- Converting to object array")
				local.result = cursorToArrayOfObjects(local.cursor);
			getTimer().stop("-- Converting to object array")
		}

		return local.result;
	}

	public any function listAsArray(struct criteria={}, string sortorder="", numeric offset=0, numeric max=0, numeric limit=0, boolean withRowCount=false) {
		arguments.asQuery = false;
		return list(argumentCollection = arguments);
	}	

	public any function listAsIterator(struct criteria={}, string sortorder="", numeric offset=0, numeric max=0, numeric limit=0, boolean withRowCount=false) {
		arguments.asQuery = false;
		arguments.iterator = true;
		return list(argumentCollection = arguments);
	}	

	public function getIterator(required ActiveEntity entity, required any cursor) {
		return new Iterator( arguments.entity, arguments.cursor );
	}

	public array function random(struct criteria={}, numeric max=3) {
		local.result = []
		getTimer().start("#getEntityName()#.random( #arguments.criteria.toString()# )")
			local.cursor = getCollection().aggregate({"$match":arguments.criteria}, {"$sample":{"size":arguments.max}}); 
			local.samples = local.cursor.results()
			for (local.sample in local.samples) {
				local.entity = _entityNew();
				this.populateFromDoc(local.entity, local.sample)
				local.result.append( local.entity );
			}
		getTimer().stop("#getEntityName()#.random( #arguments.criteria.toString()# )")
		return local.result;
	}

	public numeric function count(struct criteria={}) {
		getTimer().start("#getEntityName()#.count( #arguments.criteria.toString()# )")
			var result = getCollection().count(arguments.criteria);
		getTimer().stop("#getEntityName()#.count( #arguments.criteria.toString()# )")
		return result;
	}

	public any function aggregate() {
		var pipeline = [];
		if (isArray(arguments[1])) {
			pipeline = arguments[1];
			getTimer().start("#getEntityName()#.aggregate()")
				if (!isnull(arguments[2])) 
					var result = getCollection().aggregate(pipeline,arguments[2]);
				else 
					var result = getCollection().aggregate(pipeline).results();
			getTimer().stop("#getEntityName()#.aggregate()")
		}
		else {
			loop array="#arguments#" item="local.arg" index="local.i" {
				pipeline.append( local.arg );
			}
			getTimer().start("#getEntityName()#.aggregate()")
				var result = getCollection().aggregate(pipeline).results();
			getTimer().stop("#getEntityName()#.aggregate()")
		}
 
		return result;
	}

	public ActiveEntity function save() {
		preSave();
		
		var doc = getMemento( forPersisting:true );
		var query = { "_id":doc["_id"] };

		getCollection().update( query, doc, true );
		
		postSave();
		return this;
	}

	public numeric function deleteAll() {
		local.result = getCollection().remove({});
		return local.result.getN();
	}

	public numeric function delete() {
		local.result = getCollection().remove({"_id":_mongoID(this.getID())})
		return local.result.getN();
	}
	
	any function populate(required struct memento, string scope="", boolean trustedSetter=true, string include="", string exclude="", boolean ignoreEmpty=false){

		// remove nulls from memento, they choke populator
		for (var key in listtoarray(structkeylist(memento))) {
			if (!structkeyexists(memento,key)) structDelete(memento, key);
		}

		arguments.target = this;
		return getWirebox().getObjectPopulator().populateFromStruct(argumentCollection=arguments);
	}

	cbvalidation.models.result.ValidationResult function validate(string fields="*", any constraints="", string locale="", string excludeFields="") {
		this.isValid(argumentCollection:arguments);
		return this.getValidationResults();
	}

	boolean function isValid(string fields="*", any constraints="", string locale="", string excludeFields=""){
		// Get validation manager
		var validationManager = getWirebox().getInstance("ValidationManager@cbvalidation");
		// validate constraints
		var thisConstraints = "";
		if( structKeyExists(this,"constraints") ){ thisConstraints = this.constraints; }
		// argument override
		if( !isSimpleValue(arguments.constraints) OR len(arguments.constraints) ){
			thisConstraints = arguments.constraints;
		}

		// validate and save results in private scope
		validationResults = validationManager.validate(target=this, fields=arguments.fields, constraints=thisConstraints, locale=arguments.locale, excludeFields=arguments.excludeFields);

		// return it
		return ( !validationResults.hasErrors() );
	}

	cbvalidation.models.result.ValidationResult function getValidationResults(){
		if( structKeyExists(variables,"validationResults") ){
			return validationResults;
		}
		return new cbvalidation.models.result.ValidationResult();
	}

	/* for implicit get/set/add/remove/has functions */     
	public any function onMissingMethod(missingMethodName, missingMethodArguments) {
		local.matcher = reFindNoCase("^(get|set|add|remove|has)(.*)$", arguments.missingMethodName, 0, true);

		if (arraylen(local.matcher.len) lt 3) {
			throw(type="MissingMethod",detail="#getMetaData(this).name# has no public method #arguments.missingMethodName#()");
		}

		// extract the operation (get/set/add/remove/has)
		var operation = mid(arguments.missingMethodName, local.matcher.pos[2], local.matcher.len[2]);
		// extract the property name
		var target = mid(arguments.missingMethodName, local.matcher.pos[3], local.matcher.len[3]);
		// extract the property metadata
		var properties = getEntityProperties();
		var targetProperty = properties.keyExists(target) ? properties[target] : {};

		if (!structkeyexists(targetProperty,"type"))
			targetProperty.type="any";

		switch(operation){
			case "get":

				var mongoRelationType = structKeyExists(targetProperty, "mongorel") ? targetProperty.mongorel : "none";
				if (!isnull(arguments.missingMethodArguments["lazy"]) && arguments.missingMethodArguments["lazy"]) {
					mongoRelationType = "none"; // force get raw uninflated value
				}

				if (mongoRelationType eq "none")
					return structKeyExists(variables,target) ? variables[target] : nullValue();
				if (mongoRelationType eq "linked")
					return getLinkedDocs( target, targetProperty );
				if (mongoRelationType eq "embedded")
					return getEmbeddedDocs( target, targetProperty );

			break;

			case "set":


				if (not structkeyexists(targetProperty,"mongorel")) {
					// convert empty strings to nulls
					if (!isnull(arguments.missingMethodArguments[1]) && isSimpleValue(arguments.missingMethodArguments[1]) && !len(trim(arguments.missingMethodArguments[1])))
						arguments.missingMethodArguments[1] = nullValue()

					// convert empty arrays & structs to nulls
					if (!isnull(arguments.missingMethodArguments[1]) && (isArray(arguments.missingMethodArguments[1]) || isStruct(arguments.missingMethodArguments[1])) && !arguments.missingMethodArguments[1].len())
						arguments.missingMethodArguments[1] = nullValue()

					if (isnull(arguments.missingMethodArguments[1])) {
						variables[target] = nullValue();
					} else {
						if (targetProperty.type=="numeric") {
							variables[target] = javacast("numeric",trim(arguments.missingMethodArguments[1]));
						} else if (targetProperty.type=="boolean") {
							variables[target] = javacast("boolean",trim(arguments.missingMethodArguments[1]));
						} else {
							variables[target] = getmetaData(arguments.missingMethodArguments[1]).getname() == "java.lang.String" ? trim(arguments.missingMethodArguments[1]) : arguments.missingMethodArguments[1];
						}
					}
				} else if ( targetProperty.mongorel == "linked" ) {
					return setLinkedDocs( target, targetProperty, arguments.missingMethodArguments[1] );
				} else if ( targetProperty.mongorel == "embedded" ) {
					return setEmbeddedDocs( target, targetProperty, arguments.missingMethodArguments[1] );
				}

				return this;
			break;
		
			default:
				throw(type="MissingMethod",detail="#operation# not yet supported in ActiveEntity (#target#)");
			break;
		}

		return;
	}

	public void function ensureIndexes(
										boolean dropDups, 
										boolean forceReindex, 
										collection=getCollection(), // allows us to create indexes on a temp version of the collection
										boolean background=true 
									){
		var fields = getMongoHelpers().MongoDBObjectBuilder()
		var options = {}
		var logbox = getLogBox().getLogger(this);

		if (isnull(this.getCollectionName()))
			return;

		if (arguments.forceReindex?:false){
			if (logbox.canWarn())
				logbox.warn("mongoentity: dropped all indexes on #getCollectionName()#");
			
			local.timer = "&nbsp;&nbsp;&nbsp;&nbsp;...dropIndexes #getCollectionName()#";
			getTimer().start(local.timer);
			collection.dropIndexes();
			getTimer().stop(local.timer);
		}

		for (var index in getCollectionIndexes()) {
			fields = getMongoHelpers().MongoDBObjectBuilder()
			options = {}

			index.fields.each(function(field){
				if (isSimpleValue(field)){
					fields.add("#field#",1)
				}
				else {
					for (local.key in field) {
						fields.add("#local.key#",field[local.key])
					}
				}
			});

			options["background"] = arguments.background;
			options["name"] = index.name;
			options["unique"] = index.unique ?: false;

			if (!isnull(index.partialFilterExpression))
				options["partialFilterExpression"] = index.partialFilterExpression;
			else 
				options["sparse"] = index.sparse ?: false;

			if (!isnull(arguments.dropDups))
				options["dropDups"] = arguments.dropDups;

			local.timer = "&nbsp;&nbsp;&nbsp;&nbsp;...index #getCollectionName()#.#index.name#" & (options.background ? " (background)" : "");
			getTimer().start(local.timer);
				try {
					collection.createIndex( fields.get(), options )
					if (logbox.canInfo())
						logbox.info("mongoentity: ensured index #getCollectionName()#.#index.name#");
				} catch (Any local.e) {
					try {
						collection.dropIndex( index.name );
						collection.createIndex( fields.get(), options );
						if (logbox.canWarn())
							logbox.warn("mongoentity: dropped and rebuilt index #getCollectionName()#.#index.name#");
					} catch (any local.ee) {
						throw(argumentCollection:local.e);
					}
				}
			getTimer().stop(local.timer);
		}
	}

	public date function getDateFromID(){
		local.result = MongoDBID( this.getID() ).getDate()
		return local.result;
	}    
	
	/* ----------------------------------------------- PRIVATE --------------------------------------------- */


	private any function _mongoID(id) {
		if (!isSimpleValue(arguments.id)) return arguments.id;

		var result = arguments.id;

		try {
			// try to convert to a mongo ID
			result = MongoDBID(arguments.id);
		} catch (Any e) { 
			// failed, not a valid mongo ObjectID string, just return the original string
			return arguments.id;
		}

		return result;
	}

	private component function _entityNew(string entity=getEntityName(), string componentPath) {
		if (!isnull(componentPath)) {
			var result = createObject("component", componentPath).init();
			getWirebox().autowire(target:result, targetID:componentPath);
			return result;
		}

		return getWirebox().getInstance(entity);
	}

	public query function cursorToQuery(required any cursor) {
		var result = querynew("_id,#getEntityProperties().keyList()#");
		var row = {};
		var col = "";
		while (arguments.cursor.hasNext()) {
			row = arguments.cursor.next();
			queryaddrow(result);
			for ( col in row ) {
				if (not listfindnocase(result.columnlist,col)) queryAddColumn(result, col, []);
				if (col == "_id") {
					querySetCell(result, "id", isStruct(row[col]) ? row[col] : row[col].toString() );
				}
				querySetCell(result, col, !structkeyexists(row,col) ? nullvalue() : row[col] );
			}
		}
		return result;
	}

	public array function cursorToArrayOfObjects(required any cursor) {
		var result = [];
		if (!arguments.cursor.size())
			return result;
			
		var entity = "";
		var doc    = "";
		while (arguments.cursor.hasNext()) {
			entity = _entityNew();
			populateFromDoc(entity, arguments.cursor.next());
			result.append( entity )
		}
		return result;
	}

	private any function getEmbeddedMementos(required any embedded, required boolean forPersisting) {
		var result = arguments.embedded;

		if (isArray(arguments.embedded)) {
			result = [];
			for (var i=1; i lte arguments.embedded.len(); i++) {
				result[i] = getEmbeddedMementos(arguments.embedded[i], arguments.forPersisting);
			}
		}

		if (isStruct(arguments.embedded)) {
			result = structnew("linked");
			
			for (var key in arguments.embedded) {
				if (structkeyexists(arguments.embedded,key)) {
					result[key] = arguments.embedded[key];
					
					if (isEmpty(result[key]))
						structdelete(result,key);
				}
			}
		}

		if (arguments.forPersisting && !result.len())
			return; // return null for empty arrays & structs

		return result;
	}

	public struct function getMemento(boolean forPersisting=false) {
		var result = structnew("linked");
		var props = getInheritedProperties( getMetaData(this) );
		for (var prop in props) {
			if ((prop.persist?:true) || !arguments.forPersisting) {
				
				if (structkeyexists(variables,prop.name)) {
					if (structkeyexists(prop,"mongorel") && prop.mongorel == "embedded") {
						local.embeddedMemento = getEmbeddedMementos(variables[prop.name], arguments.forPersisting)
						if (!isnull(local.embeddedMemento))
							result[prop.name] = local.embeddedMemento
					} else {
						if (!isEmpty(variables[prop.name]))
							result[prop.name] = variables[prop.name];                    
					}
				}

				// add _id=objectID if id is "generated"
				if (prop.name == "id" && !isnull(getCollectionName()) && (prop.generator?:"") == "native" && arguments.forPersisting) {
					if (isnull(this.getID())) {
						// we have no ID yet, so autogenerate one
						result["_id"] = MongoDBID();
						// set the id copy
						this.setID( result["_id"].toString() );
					} else {
						// we have an ID, use it
						result["_id"] = _mongoID(this.getID());
					}
				}
			}
		}

		// if we don't have _id yet, set it to ID
		if (!isnull(getCollectionName()) && not structKeyExists(result, "_id")) result["_id"] = this.getID();

		// clean up the string ID, so we don't persist it
		if (!isnull(getCollectionName()))
			structdelete(result,"id");

		return result;
	}

	public void function populateFromDoc(component entity, struct doc) {
		var docNoNulls = {}
		if (structkeyexists(arguments.doc,"_id")) {
			if (isSimpleValue(arguments.doc["_id"]) || isStruct(arguments.doc["_id"]))
				arguments.doc["id"] = arguments.doc["_id"];
			else
				arguments.doc["id"] = arguments.doc["_id"].toString();
		}

		for (local.key in arguments.doc) {
			if (structkeyexists(arguments.doc,local.key)) docNoNulls[local.key] = arguments.doc[local.key]
		}

		local.properties = arguments.entity.getVariables();

		for (local.key in docNoNulls) {
			local.properties[local.key] = docNoNulls[local.key]
		}
		return;
	}

	private any function getLinkedDocs(required string target, required struct targetProperty) {

		if (structkeyexists(variables,"#target#_objectified")) {
			return variables["#target#_objectified"];
		}
		
		var result = "";
		var type = structKeyExists(targetProperty, "type") ? targetProperty.type : "any";

		switch (type) {
			case "array":
				result = [];
				if (!structkeyexists(variables,target)) return result;

				var criteriaValues = [];
				var criteriaKey = "_id";
				for ( var ii in variables[target]) {
					if (targetProperty.joinColumn == "id") {
						criteriaValues.append( _mongoID(ii) );
					} else {
						criteriaValues.append( ii );
						criteriaKey = targetProperty.joinColumn;
					}
				}

				if (targetProperty.keyExists("cfc")) {
					local.entity = _entityNew(componentPath:targetProperty.cfc);
				} else {
					local.entity = _entityNew(targetProperty.mongoentity);
				}

				var unorderedResults = local.entity.list(criteria:{"#criteriaKey#":{"$in":criteriaValues}}, asQuery:false, withRowCount:false);
				var idMap = {};
				for (local.obj in unorderedResults) {
					idMap[local.obj.getVariables()[criteriaKey]] = local.obj;
				}

				for (ii in variables[target]) {
					result.append( idMap[ii] );
				}
			break;
		
			default:
				if (!structkeyexists(variables,"#target#_entity"))
					variables["#target#_entity"] = targetProperty.keyExists("cfc") ? _entityNew(componentPath:targetProperty.cfc) : _entityNew(targetProperty.mongoentity);

				local.entity = variables["#target#_entity"].reset();

				// if property is null, return an empty object
				if (!structkeyexists(variables,target)) return local.entity;
				if (targetProperty.joinColumn == "id") {
					result = local.entity.findWhere({ "_id":_mongoID(variables[target]) });
				} else {
					var criteria = { "#targetProperty.joinColumn#"=variables[target] }
					result = local.entity.findWhere(criteria);
				}
				// if we don't have a result yet, no linked document(s) exist with FK, return empty object
				if ( isnull(result) ) result = local.entity;
			break;
		}

		variables["#target#_objectified"] = result;

		return result;
	}
	
	private any function getEmbeddedDocs(required string target, required struct targetProperty) {

		if (structkeyexists(variables,"#target#_objectified")) {
			return variables["#target#_objectified"];
		}

		var result = "";
		var type = structKeyExists(targetProperty, "type") ? targetProperty.type : "any";

		switch(type) {
			case "array":
				result = [];
				if (!structkeyexists(variables,target)) return result;
				for ( var ii in variables[target]) {
					local.item = targetProperty.keyExists("cfc") ? _entityNew(componentPath:targetProperty.cfc) : _entityNew(targetProperty.mongoentity);
					populateFromDoc(local.item, ii)
					result.append( local.item )
				}
			break;
		
			default:
				if (!structkeyexists(variables,"#target#_entity"))
					variables["#target#_entity"] = targetProperty.keyExists("cfc") ? _entityNew(componentPath:targetProperty.cfc) : _entityNew(targetProperty.mongoentity);

				result = variables["#target#_entity"].reset();
				// if property is null, return an empty object
				if (!structkeyexists(variables,target)) return result;

				// otherwise, populate it
				populateFromDoc( result, variables[target] );
			break;
		}

		variables["#target#_objectified"] = result;
		return result;
	}
	
	private any function setLinkedDocs(required string target, required struct targetProperty, any value) {
		var type = structKeyExists(targetProperty, "type") ? targetProperty.type : "any";

		switch(type) {
			case "array":
				var result = [];
				for ( var ii in arguments.value) {
					if ( isObject(ii) ) {
						arrayappend( result, evaluate("ii.save().get"&targetProperty.joinColumn&"()") );
					} else {
						arrayappend(result,ii)
					}
				}

				structdelete(variables,"#target#_objectified");
				variables[target] = result;
			break;
		
			default:
				var result = "";
				if (!isnull(arguments.value) && isObject(arguments.value)) {
					result = evaluate("arguments.value.save().get"&targetProperty.joinColumn&"()"); 
				} else {
					variables[target] = arguments.value;
					structdelete(variables,"#target#_objectified");
					return this;
				}

				variables[target] = result;
			break;
		}

		return this;
	}

	private any function setEmbeddedDocs(required string target, required struct targetProperty, any value) {
		
		var type = structKeyExists(targetProperty, "type") ? targetProperty.type : "any";

		switch(type) {
			case "array":
				arguments.value = arguments.value?:[] // default nulls to empty array
				var result = [];
				for ( var ii in arguments.value ) {
					var item = {}
					if ( isObject(ii) ) {
						item = structnew("linked");
						var props = ii.getEntityProperties();
						for ( var prop in props ) {
							if (!structkeyexists(props[prop],"persist") || props[prop].persist == true) {
								item[props[prop].name] = evaluate( "ii.get#props[prop].name#()" );
								if (!isnull(item[props[prop].name]) && isInstanceOf(item[props[prop].name],"ActiveEntity"))
									item[props[prop].name]=item[props[prop].name].getMemento(forPersisting:true);
								if (isnull(item[props[prop].name]))
									structdelete(item,props[prop].name);
							}
						} 
						arrayappend( result, item );
					} else {
						arrayappend( result, ii );
					}
				}

				structdelete(variables,"#target#_objectified");
				variables[target] = result;
			break;
		
			default:
				arguments.value = arguments.value?:{} // default nulls to empty struct
				var result = structnew("linked");
				if (isObject(arguments.value)) {
					result = structnew("linked");
					var props = arguments.value.getEntityProperties();
					for ( var prop in props ) {
						if (!structkeyexists(props[prop],"persist") || props[prop].persist == true)
							result[props[prop].name] = evaluate( "arguments.value.get#props[prop].name#(lazy:true)" )
						
						if (isnull(result[props[prop].name]))
							structdelete(result,props[prop].name);
					} 
				} else {
					variables[target] = arguments.value;
					// in case "expanded" version exists, remove it so it will repopulate on next get()
					structdelete(variables,"#target#_objectified");
					return this;
				}

				variables["#target#_objectified"] = arguments.value;
				variables[target] = result;
			break;
		}

		return this;
	}

	private array function getInheritedProperties(required struct metadata) {
		if (isnull(variables.inheritedproperties)) {
			var inheritedproperties = [];
			var prop = {};

			local.extends = true;
			local.comMD = metadata;
			
			while (local.extends) {
				for (prop in (local.comMD.properties?:[])) {
					inheritedproperties.append( prop );
				}
				if (local.comMD.keyExists("extends"))
					local.comMD = local.comMD.extends;
				else 
					break;
			}

			variables.inheritedproperties = inheritedproperties;
		}
	
		return variables.inheritedproperties;
	}

	/* ----------------------------------------------- EVENT HANDLERS --------------------------------------------- */    

	private any function preSave(){
		if ( structkeyexists(variables,"timestampProperty") && !isnull(this.getID()) )
			variables[variables.timestampProperty] = now();
	}

	private any function postSave(){}
	
}