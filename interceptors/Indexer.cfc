component output="false" extends="coldbox.system.Interceptor"  {

	public function configure(){
		return this;
	}
	
	public void function afterConfigurationLoad(event,interceptData){
		if (!getModuleSettings("mongoentity").get("ensureIndexesOnInit")) {
			return;
		}
		
		runEvent("mongoentity:Main.ensureindexes");
	}
}