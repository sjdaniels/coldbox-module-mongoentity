component hint="Scans model locations and binds ActiveEntity objects by name" singleton {

	property name="wirebox" inject="wirebox";

	public array function mapEntities(required struct scanLocations, string moduleNamespace) {
		var entities = {};
		var mapped = [];

		loop collection="#scanLocations#" item="local.location" index="local.i" {
			local.models = directoryList(path:local.location,recurse:true,listinfo:"path",filter:"*.cfc");
			loop array="#local.models#" item="local.model" {
				if (isnull(arguments.moduleNamespace)) {
					local.componentPath = getDirectoryFromPath(local.model).replace( local.location, local.i & "/", 'all').replace("/",".","all");
					local.component = local.componentPath & (local.componentPath.right(1)=="."?"":".") & getFileFromPath(local.model).replace('.cfc','');
				}
				else {
					local.componentPath = getDirectoryFromPath(local.model).replace( local.location, local.i, 'all').replace("/",".","all");
					local.component = arguments.moduleNamespace & "." & local.componentPath & (local.componentPath.right(1)=="."?"":".") & getFileFromPath(local.model).replace('.cfc','');
				}

				try {
					local.obj = createobject("component",local.component);
				}
				catch (any local.e) {
					// CFC is not a component (i.e. interfaces)
					continue;
				}
				local.metadata = getMetaData(local.obj);
				local.extends = local.metadata.extends?:""
				local.isEntity = false;
				while (true) {
					if (isSimpleValue(local.extends))
						break;

					if (local.extends.name=="mongoentity.models.ActiveEntity"){
						local.isEntity = true;
						break;
					}

					local.extends = local.extends.extends?:"";
				}

				if (local.isEntity){
					local.entityname = local.metadata.entityname ?: local.metadata.name.listlast(".");
					if (!isnull(arguments.moduleNamespace))
						local.entityname = local.entityname & "@" & arguments.moduleNamespace;
					
					if (entities.keyexists(local.entityname)){
						throw(message:"ActiveEntity Name Collision",extendedinfo:"ActiveEntity named #local.entityname# already exists (#entities[local.entityname]# - conflicts with #local.metadata.name#)!");
					}
					entities[local.entityname] = local.metadata.name;
				}
			}
		}

		var Injector = wirebox.getBinder();
		for (var entity in entities) {
			Injector.map(entity).to(entities[entity]);
			mapped.append(entity);
		}

		return mapped;
	}

}