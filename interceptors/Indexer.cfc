component output="false" extends="coldbox.system.Interceptor"  {

    public function configure(){
    	variables.indexEnsured = [];
        variables.timer = getInstance("timer@cbdebugger");
        return this;
    }
    
    public void function afterConfigurationLoad(event,interceptData){
    	for (var entityname in getSetting("mongoentities")) {
    		local.tick = getTickCount();
    		getInstance(entityName).ensureIndexes();
    		log.info("Ensured indexes on #entityName# - #getTickCount()-local.tick#ms");
    	}
    }
}