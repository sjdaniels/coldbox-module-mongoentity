component output="false" extends="coldbox.system.Interceptor"  {

	public function configure(){
		variables.indexEnsured = [];
		return this;
	}
	
	public void function afterConfigurationLoad(event,interceptData){
		if (!getModuleSettings("mongoentity").get("ensureIndexesOnInit")) {
			return;
		}
		
		for (var entityname in getSetting("mongoentities")) {
			local.tick = getTickCount();
			getInstance(entityName).ensureIndexes();
			if (log.canDebug())
				log.debug("Ensured indexes on #entityName# - #getTickCount()-local.tick#ms");
		}
	}
}