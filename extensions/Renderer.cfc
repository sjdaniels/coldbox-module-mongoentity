component extends="coldbox.system.web.Renderer" {

	/**
	* Render a view composed of collections, mostly used internally, use at your own risk.
	*/
	function renderViewCollection(
		view,
		viewPath,
		viewHelperPath,
		args,
		collection,
		collectionAs,
		numeric collectionStartRow=1,
		numeric collectionMaxRows=0,
		collectionDelim=""
	){
		var buffer 	= createObject( "java", "java.lang.StringBuilder" ).init();
		var x 		= 1;
		var recLen 	= 0;

		if (!isInstanceOf(arguments.collection, "Iterator"))
			return super.renderViewCollection(argumentCollection=arguments);

		var isAggCursor = false;
		
		try {
			recLen = arguments.collection.len();
		}
		catch (any var e) {
			isAggCursor = true;
		}
		
		// zero index for cursor
		arguments.collectionStartRow--;

		if (!isAggCursor) {

			if (arguments.collectionStartRow)
				arguments.collection.skip( arguments.collectionStartRow );

			// is max rows passed?
			if( arguments.collectionMaxRows NEQ 0 AND arguments.collectionMaxRows LTE recLen ){ 
				recLen = arguments.collectionMaxRows; 
				arguments.collection.limit( arguments.collectionMaxRows );
			}
		}

		// Create local marker
		variables._items	= recLen;
		// iterate and present
		while ( arguments.collection.hasNext() ) {
			variables._counter = arguments.collection.currentrow();
			variables[ arguments.collectionAs ] = arguments.collection.next();
			
			if (isAggCursor && arguments.collectionMaxRows && (variables._counter lt arguments.collectionStartRow || variables._counter gte (arguments.collectionStartRow+arguments.collectionMaxRows)))
				continue;
			
			// prepend the delim
			if ( variables._counter NEQ arguments.collectionStartRow ) {
				buffer.append( arguments.collectionDelim );
			}
			// render item composite
			buffer.append( renderViewComposite( arguments.view, arguments.viewPath, arguments.viewHelperPath, arguments.args ) );
		}

		// can use this to get "total rows" count for aggregation cursors
		prc.totaliterations = variables._counter ?: 0;

		return buffer.toString();
	}
}