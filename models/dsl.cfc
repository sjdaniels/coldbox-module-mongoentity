component output="false" implements="coldbox.system.ioc.dsl.IDSLBuilder"  {

    public function init(required any injector) output=false {
        variables.injector = arguments.injector;
        return this;
    }

    public any function process(required any definition, any targetObject) output=false {
        var thisType = arguments.definition.dsl
        var thisTypeLen = listlen(thisType,":");


        // return a generic Mongo Service object
        if (thisTypeLen == 1) return variables.injector.getInstance("commons.models.mongo.entityService.BaseMongoService");

        // return the specific object requested
        return variables.injector.getInstance(listlast(thisType,":"));
    }

}