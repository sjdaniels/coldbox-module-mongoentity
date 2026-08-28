component {

	this.title 				= "mongoentity";
	this.author 			= "Sean Daniels";
	this.description 		= "ActiveEntity like interface for MongoDB collections";
	this.version			= "1.0.0";
	this.entryPoint			= "mongoentity";
	this.modelNamespace		= "mongoentity";
	this.cfmapping			= "mongoentity";

	function configure(){
		// Interceptors
		interceptors = [
			{ class="#moduleMapping#.interceptors.Indexer", name="indexer@#this.modelNamespace#" }
		];

		// module settings - stored in modules.name.settings
		settings = {
			 ensureIndexesOnInit:true

			// Lost-update auditing (Phase 0). Observation only - it never changes what save() writes.
			// Costs one extra read per save of an audited collection, so it is opt-in per collection
			// and meant to be switched back off once the numbers are in.
			// See models/LostUpdateAudit.cfc.
			// collections maps name -> sample rate (0..1), the share of HYDRATIONS that keep a
			// snapshot. Sampling is the cost lever: the snapshot is a duplicate() of the document,
			// paid per hydrated document, and collections that are read in bulk and written rarely
			// (posts: ~7.6KB average, hydrated 50 at a time by browse and search, saved only on
			// edit) would otherwise pay a large read-path cost for a rare write-path signal.
			// Findings from a sampled collection are a sample - scale up when reading the numbers.
			,lostUpdateAudit:{
				 enabled		: false
				,collections	: {}								// e.g. { "members":1, "posts":0.1 }
				,logCollection	: "mongoentity_lostupdates"
				,ignoreFields	: []								// add high-churn fields after round one
				,maxValueChars	: 500
				,ttlDays		: 30								// self-expiring log; 0 disables the TTL index
			}
		};
	}

	function onLoad(){
		var mapper = wirebox.getInstance("#moduleMapping#.models.AutoMapper");
		var mapped = mapper.mapEntities( wirebox.getBinder().getScanLocations() );
		controller.setSetting("mongoentities", mapped);

		// publishes the application-scope gate populateFromDoc() reads. Instantiated here rather than
		// lazily so the gate matches the settings from the first request after a reinit.
		wirebox.getInstance("LostUpdateAudit@mongoentity").configure();
	}

	function onUnload(){
	}
}