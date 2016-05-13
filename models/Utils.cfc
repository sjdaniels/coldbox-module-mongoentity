component output="false" singleton {

	function MongoDBObject(){
		var DBObject = MongoDBObjectBuilder();
		var key = "";

		for (key in arguments) {
			DBObject.append( key, arguments[key] )
		}

		return DBObject.get();
	}

	function toCF(any key required) {
		var result = arguments.key;
		if (isArray(arguments.key)) {
			result = [];
			for (local.i in arguments.key) {
				arrayappend(result, isnull(local.i)? nullvalue(): toCF(local.i));
			} 
		}

		if (isStruct(arguments.key)) {
			result = structnew("linked");
			for (local.i in arguments.key) {
				result[local.i] = !structkeyexists(arguments.key,local.i)? nullvalue(): toCF(arguments.key[local.i]);
			}
		}

		return result;
	}

    function MongoDBObjectBuilder(){

    	return createobject("java","com.mongodb.BasicDBObjectBuilder").start()
    }

    function MongoDayCriteria(required date theDate, boolean asObjectIDs=false){
		var thenextDate = arguments.theDate.add("d",1)
		var result = {"$gte":createdate(thedate.year(),thedate.month(),thedate.day()),"$lt":createdate(thenextdate.year(),thenextdate.month(),thenextdate.day())}

		if (arguments.asObjectIDs){
			result["$gte"] = MongoDBID(result["$gte"])
			result["$lt"] = MongoDBID(result["$lt"])
		}

		return result; 	
    }

    struct function sortFormat(any sortorder) {
		if (!isSimpleValue(arguments.sortorder))
			return arguments.sortorder;

		local.result = MongoDBObjectBuilder()
        if (len(trim(arguments.sortorder))) {
            for (local.sorttoken in listtoarray(arguments.sortorder)) {
                local.sortcol = getToken(local.sorttoken,1," ");
                local.sortdir = findnocase("desc",local.sorttoken) ? -1 : 1;
                local.result.add(local.sortcol,local.sortdir);
            }
        }
   	
   		return local.result.get();
    }

    numeric function getDistanceBetweenGeoPoints(required array point1, required array point2) {
		local.lat1 = point1[2]
		local.lon1 = point1[1]
		local.lat2 = point2[2]
		local.lon2 = point2[1]

		if (local.lat1==local.lat2 && local.lon1==local.lon2)
			return 0;

		// in meters
		local.distance = ACOS( SIN(local.lat1)*SIN(local.lat2) + COS(local.lat1)*COS(local.lat2)*COS(local.lon2-local.lon1) ) * 6371000;
		return local.distance;
    }
}