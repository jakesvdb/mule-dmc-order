%dw 2.0
import * from dw::core::Strings
output application/json

var shipMethod = "FEDEX_GROUND"
var recipientType = "Salesforce"
var defaultAddress = "130 Default Road"
var defaultCity = "Default"
var defaultState = "PA"
var defaultPostalCode = "19087"
var defaultPhone = "888-888-88888"
var sourceSystem="DMC"
var contactPreferenceType="ContactEmailAddresses"
var isVDP = false as Boolean
var hasKits = false as Boolean

var fileInfo = payload.DeliveryOutput.Files.*FileInfo
var fileContentInfo = payload..*ContentInfo
var documentInfo = payload.DeliveryOutput.DeliveryOption.DeliveryFields.*Field.TableColumns.*DeliveryFieldTableColumnInfo
var deliveryFields = payload.DeliveryOutput.DeliveryOption.DeliveryFields
var contentStatus = payload.DeliveryOutput.DeliveryApproval.*Recipients.*ContentStatus
var recipients = payload.DeliveryOutput.DeliveryApproval.*Recipients
var name_files = recipients map (recipient, index) -> {
    recipientName: recipient.FirstName ++ " " ++ recipient.LastName,
    recipientEmail: recipient.Email,
    recipientCompany: recipient.Company,
    contentStatus: recipient.*ContentStatus,
    recipientStatus: recipient.RecipientStatus.Status,
    contextStatus: recipient.Context
        
}
var retrieveAttribute = (element, attrName) -> 
		element filterObject ((value, key, index) -> (key.@Name == attrName))
var retrieveCustomProperty = (element, attrName) -> 
		element filterObject ((value, key, index) -> (key.@Name == attrName))
var requesterName = retrieveAttribute(deliveryFields, "UserFirstName").Field.@Value ++ " " ++
	retrieveAttribute(deliveryFields, "UserLastName").Field.@Value
var costCenterCode = if (retrieveAttribute(deliveryFields, "ShipMethod").Field.@Value == shipMethod)
						retrieveAttribute(deliveryFields, "DefaultShippingDSU").Field.@Value
			  		 else 
			  			retrieveAttribute(deliveryFields, "ShippingDSU").Field.@Value
var zip5 = (zip) -> if (zip contains "-") 
						substringBefore(zip, "-")
					else
						zip	
						
var zip4 = (zip) -> if (zip contains "-") 
						substringAfter(zip, "-")
					else
						""
fun getDefault(inputdata, otherdata, defaultValue) = 
	if ((inputdata != null and sizeOf(inputdata default[]) > 0)) 
		otherdata 
	else 
		defaultValue
		
fun useDefault(address, city, state, postalcode, phone) = 
	if ((isEmpty(address) or isEmpty(city) or isEmpty(state) or isEmpty(postalcode)) and isEmpty(phone))
		key : { 
			Address1: defaultAddress,
			City: defaultCity,
			State: defaultState,
			PostalCode: defaultPostalCode,
			Phone: defaultPhone
			
			}
	else
	if ((isEmpty(address) or isEmpty(city) or isEmpty(state) or isEmpty(postalcode)) and (not isEmpty(phone)))
		key : { 
			Address1: defaultAddress,
			City: defaultCity,
			State: defaultState,
			PostalCode: defaultPostalCode,
			Phone: phone
			}
	else 
 	if ((not isEmpty(address) and not isEmpty(city) and not isEmpty(state) and not isEmpty(postalcode)) and (isEmpty(phone)))
		key : { 
			Address1: address,
			City: city,
			State: state,
			PostalCode: postalcode,
			Phone: defaultPhone
			}
	else 
		key : { 
			Address1: address,
			City: city,
			State: state,
			PostalCode: postalcode,
			Phone: phone
			}
        
---


{
	orders: 
		name_files reduce (  
			(file, result=[]) -> (
				result ++ (
					file.contentStatus map (content, index) -> { 
						SourceSystem: sourceSystem,
						SourceSystemIdentifier: payload.DeliveryOutput.Files.*FileInfo.RequestId[0],
						OrderedAt: (payload.DeliveryOutput.RequestInfo.Timestamp as LocalDateTime {format: "M/d/y h:m:s a"}) as LocalDateTime {format: "MM/dd/yyyy HH:mm:ss"},
						ShipOn: retrieveAttribute(deliveryFields, "MailDate").Field.@Value,
						Requester: {
							SourceSystemIdentifier:retrieveAttribute(deliveryFields, "UserSalesforceId").Field.@Value,
							Name: requesterName,
							EmailAddress: retrieveAttribute(deliveryFields, "UserEmail").Field.@Value,
							PhoneNumber: retrieveAttribute(deliveryFields, "UserPhone").Field.@Value,
						},
						ContactPreferenceType: contactPreferenceType,
						ContactEmailAddresses: (retrieveAttribute(deliveryFields, "UserEmail").Field.@Value splitBy(",")),
						CreatedByEmailAddress: retrieveAttribute(deliveryFields, "UserEmail").Field.@Value,
						PrintCostCenterCode: retrieveAttribute(deliveryFields, "UserDSU").Field.@Value,
						ShipCostCenterCode: costCenterCode,                                           			      
						Recipient: if (retrieveAttribute(deliveryFields, "RecipientType").Field.@Value == recipientType) {
							SourceSystemIdentifier: file.contextStatus.ContextId,
							Name: file.recipientName,
							MailingAddress: {
								Line1: file.contextStatus.Fields.OtherStreet,
								Line2: "",
								City: file.contextStatus.Fields.OtherCity,
								State: file.contextStatus.Fields.OtherState,
								ZipCode: zip5(file.contextStatus.Fields.OtherPostalCode),
								ZipCodePlus4: zip4(file.contextStatus.Fields.OtherPostalCode)
							},
							EmailAddress: getDefault(file.recipientEmail,file.recipientEmail,"OMCAdministrator@email.com"),
							PhoneNumber: "",
							Company: file.recipientCompany
						}
						else
						{
							SourceSystemIdentifier: file.contextStatus.ContextId,
							Name: retrieveAttribute(deliveryFields, "ManualFirstName").Field.@Value ++ " " ++ 
							retrieveAttribute(deliveryFields, "ManualLastName").Field.@Value,
							MailingAddress: {
								Line1: retrieveAttribute(deliveryFields, "ManualMailAddress1").Field.@Value,
								Line2: retrieveAttribute(deliveryFields, "ManualMailAddress2").Field.@Value default "",
								City: retrieveAttribute(deliveryFields, "ManualMailCity").Field.@Value,
								State: retrieveAttribute(deliveryFields, "ManualMailState").Field.@Value,
								ZipCode: zip5(retrieveAttribute(deliveryFields, "ManualMailPostalCode").Field.@Value),
								ZipCodePlus4: zip4(retrieveAttribute(deliveryFields, "ManualMailPostalCode").Field.@Value)
							},
							EmailAddress: getDefault(retrieveAttribute(deliveryFields, "ManualEmail").Field.@Value,
								retrieveAttribute(deliveryFields, "ManualEmail").Field.@Value, "OMCAdministrator@email.com"),
							PhoneNumber: retrieveAttribute(deliveryFields, "ManualPhoneNumber").Field.@Value default "",
							Company: retrieveAttribute(deliveryFields, "ManualCompanyName").Field.@Value default ""
						},
						ShipVia: retrieveAttribute(deliveryFields, "ShipMethod").Field.@Value,
						ShippingLabel: retrieveAttribute(deliveryFields, "ShippingLabel").Field.@Value,

						Item: ((fileInfo filter (fileI, index) -> (
							(if (fileI.ContentInfo.IsCollaborationContent == 'True') fileI.ContentInfo.CollaborationContentId else fileI.ContentInfo.Id) == content.Id 
								and content.Status == 'approve'
								and file.recipientStatus == 'approve')) 
						
									map do { //map through fileInfo items that matched above criteria
										var cid = if ($.ContentInfo.IsCollaborationContent == 'True') $.ContentInfo.CollaborationContentId else $.ContentInfo.Id
										---
										{
						
											ItemNumber: retrieveCustomProperty($.ContentInfo.ContentProperties, "Order Code").CustomProperty,
											ConstructionState: if (not isEmpty(((documentInfo filter ($.@Name ~='ConstructionState')) ..*RowInfo filter ($.@ContentId ~= cid))[0]))
												((documentInfo filter ($.@Name ~='ConstructionState')) ..*RowInfo filter ($.@ContentId ~= cid))[0]
												else if (retrieveAttribute(deliveryFields, "RecipientType").Field.@Value == recipientType) 
													payload.DeliveryOutput.DeliveryApproval.Recipients.Context.Fields.OtherState
												else 
													retrieveAttribute(deliveryFields, "ManualMailState").Field.@Value,
											Quantity: ((documentInfo filter ($.@Name ~='Quantity')) ..*RowInfo filter ($.@ContentId ~= cid))[0] as Number,
											(PrintAssets: [
												{
													FileName:"",
													NumberOfPages: 0,
													AssetType:"",
												}
											]) if(isVDP),
											(KitParentItem:"")  if(hasKits),
											(KitPlacement:"") if(hasKits),
											(KitSequence:0)  if(hasKits),
											StapleInstructions:"",  
											SpecialInstructions:((documentInfo filter ($.@Name ~='SpecialInstructions')) ..*RowInfo filter ($.@ContentId ~= cid))[0] default ""
										}
									}) reduce (item, accmulator = {}) -> accmulator ++ item  //map returns array so use reduce to extract object


					}
				)
			)
		)
}