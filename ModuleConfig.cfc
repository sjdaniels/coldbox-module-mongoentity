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
	}

	function onLoad(){
		var mapper = wirebox.getInstance("#moduleMapping#.models.AutoMapper");
		var mapped = mapper.mapEntities( wirebox.getBinder().getScanLocations() );
		controller.setSetting("mongoentities", mapped);
	}

	function onUnload(){
	}
}