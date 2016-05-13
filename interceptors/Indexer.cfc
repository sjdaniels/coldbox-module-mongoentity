component output="false" extends="coldbox.system.Interceptor"  {

    public function configure(){
    	variables.indexEnsured = [];
        return this;
    }
    
    public void function afterInstanceCreation(event,interceptData) {
    	// this keep indexes from happening during mapping, before MongoDB is in application scope
    	if (!structkeyexists(application,"wirebox:mongoDB"))
    		return;

        if (isInstanceOf(interceptData.target,"ActiveEntity") && !variables.indexEnsured.find(getMetaData(interceptData.target).name)) {
        	var timer = getInstance("timer@cbdebugger")
        	timer.start("Ensuring indexes on #getMetaData(interceptData.target).name#")
        	interceptData.target.ensureIndexes();
        	variables.indexEnsured.append(getMetaData(interceptData.target).name);
        	timer.stop("Ensuring indexes on #getMetaData(interceptData.target).name#")
        }
    }
    
}