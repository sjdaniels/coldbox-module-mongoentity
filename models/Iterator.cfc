component {

	public Iterator function init(required ActiveEntity entity, required any cursor) {
		variables.entity = arguments.entity;
		variables.cursor = arguments.cursor;
		variables.counter = 0;
		// no size() for aggregation cursors
		try {
			variables.size = arguments.cursor.size();
		}
		catch (any var e) {}
		

		return this;
	}

	public ActiveEntity function next() {
		variables.entity.populateFromDoc( variables.entity.reset(), variables.cursor.next() );
		variables.counter++;
		return variables.entity;
	}

	public boolean function hasNext() {
		return variables.cursor.hasNext();
	}

	public numeric function len() {
		return variables.size ?: variables.cursor.hasNext();
	}

	public numeric function currentrow() {
		return variables.counter;
	}

	public void function skip(required numeric num) {
		variables.counter += arguments.num;
		variables.cursor.skip( arguments.num );
		return;
	}

	public void function limit(required numeric num) {
		variables.cursor.limit( arguments.num );
		return;
	}

	public numeric function count() {
		return variables.cursor.count();
	}
}