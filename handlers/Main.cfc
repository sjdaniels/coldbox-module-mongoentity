component {

	function ensureindexes(event,rc,prc) {
		var entities = getSetting("mongoentities");
		for (var entityname in entities) {
			local.tick = getTickCount();
			getInstance(entityName).ensureIndexes();
			if (log.canDebug())
				log.debug("Ensured indexes on #entityName# - #getTickCount()-local.tick#ms");
		}
	
		return "Ensured indexes on #numberformat(entities.len())# mongo entities.";
	}

}