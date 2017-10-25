component accessors="true" implements="cbvalidation.models.validators.IValidator" hint="Validates uniqueness in Mongo collection" singleton {

	property name="name";

	UniqueValidator function init(){
		name        = "Unique";
		return this;
	}

	/**
	* Will check if an incoming value validates
	* @validationResult.hint The result object of the validation
	* @target.hint The target object to validate on
	* @field.hint The field on the target object to validate on
	* @targetValue.hint The target value to validate
	* @validationData.hint The validation data the validator was created with
	*/
	boolean function validate(required cbvalidation.models.result.IValidationResult validationResult, required any target, required string field, any targetValue, any validationData){

		// Only validate simple values and if they have length, else ignore.
		if( isSimpleValue( arguments.targetValue ) AND len( trim( arguments.targetValue ) ) ){
			
			var targetID = arguments.target.getID();
			var Exists = arguments.target.list(criteria:{ "#arguments.field#"=arguments.targetValue });

			if (Exists.recordcount and (isnull(targetID) || Exists.id[1] neq targetID)) {
				var args = {message="The '#arguments.field#' value must be unique",field=arguments.field,validationType=getName(),validationData=arguments.validationData,rejectedValue=arguments.targetValue};
				validationResult.addError( validationResult.newError(argumentCollection=args) );
				return false; // there exists another document, with a different ID, with this value.
			}

		}

		return true;
	}

	/**
	* Get the name of the validator
	*/
	string function getName(){
		return name;
	}

}