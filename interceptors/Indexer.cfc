component output="false" extends="coldbox.system.Interceptor"  {

	public function configure(){
		variables.indexEnsured = [];
		return this;
	}
	
	public void function afterConfigurationLoad(event,interceptData){
		// for (var entityname in getSetting("mongoentities")) {
		// 	local.tick = getTickCount();
		// 	getInstance(entityName).ensureIndexes();
		// 	if (log.canInfo())
		// 		log.info("Ensured indexes on #entityName# - #getTickCount()-local.tick#ms");
		// }
	}
}