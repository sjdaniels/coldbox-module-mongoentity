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

		// zero index for cursor
		arguments.collectionStartRow--;

		if (arguments.collectionStartRow)
			arguments.collection.skip( arguments.collectionStartRow );

		recLen = arguments.collection.len();
		// is max rows passed?
		if( arguments.collectionMaxRows NEQ 0 AND arguments.collectionMaxRows LTE recLen ){ 
			recLen = arguments.collectionMaxRows; 
			arguments.collection.limit( arguments.collectionMaxRows );
		}
		// Create local marker
		variables._items	= recLen;
		// iterate and present
		while ( arguments.collection.hasNext() ) {
			variables._counter = arguments.collection.currentrow();
			variables[ arguments.collectionAs ] = arguments.collection.next();
			// prepend the delim
			if ( variables._counter NEQ arguments.collectionStartRow ) {
				buffer.append( arguments.collectionDelim );
			}
			// render item composite
			buffer.append( renderViewComposite( arguments.view, arguments.viewPath, arguments.viewHelperPath, arguments.args ) );
		}
		return buffer.toString();
    }
}