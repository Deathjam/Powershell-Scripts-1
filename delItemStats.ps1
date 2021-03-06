####################### 
<# 
.SYNOPSIS 
 Creates a Statistics Report of Items in the Deleted Item folder in a Mailbox using the  Exchange Web Services API 
 
.DESCRIPTION 
  Creates a Statistics Report of Items in the Deleted Item folder in a Mailbox using the  Exchange Web Services API 
  
 Requires the EWS Managed API from https://www.microsoft.com/en-us/download/details.aspx?id=42951

.EXAMPLE
 PS C:\>Get-DeletedItemsStats  -MailboxName user.name@domain.com -ReportFileName c:\temp\delItemStats.csv
 This Example creates a Creates a Statistics Report of Items in the Deleted Item folder in a Mailbox
#> 
function Get-DeletedItemsStats 
{ 
    [CmdletBinding()] 
    param( 
    	[Parameter(Position=0, Mandatory=$true)] [string]$MailboxName,
		[Parameter(Position=1, Mandatory=$true)] [PSCredential]$Credentials,
		[Parameter(Position=2, Mandatory=$true)] [string]$ReportFileName
    )  
 	Begin
		 {
		## Load Managed API dll  
		###CHECK FOR EWS MANAGED API, IF PRESENT IMPORT THE HIGHEST VERSION EWS DLL, ELSE EXIT
		$EWSDLL = (($(Get-ItemProperty -ErrorAction SilentlyContinue -Path Registry::$(Get-ChildItem -ErrorAction SilentlyContinue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Exchange\Web Services'|Sort-Object Name -Descending| Select-Object -First 1 -ExpandProperty Name)).'Install Directory') + "Microsoft.Exchange.WebServices.dll")
		if (Test-Path $EWSDLL)
		    {
		    Import-Module $EWSDLL
		    }
		else
		    {
		    "$(get-date -format yyyyMMddHHmmss):"
		    "This script requires the EWS Managed API 1.2 or later."
		    "Please download and install the current version of the EWS Managed API from"
		    "http://go.microsoft.com/fwlink/?LinkId=255472"
		    ""
		    "Exiting Script."
		    exit
		    } 
  
		## Set Exchange Version  
		$ExchangeVersion = [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2010_SP2  
		  
		## Create Exchange Service Object  
		$service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService($ExchangeVersion)  
		  
		## Set Credentials to use two options are availible Option1 to use explict credentials or Option 2 use the Default (logged On) credentials  
		  
		#Credentials Option 1 using UPN for the windows Account  
		#$psCred = Get-Credential  
		$creds = New-Object System.Net.NetworkCredential($Credentials.UserName.ToString(),$Credentials.GetNetworkCredential().password.ToString())  
		$service.Credentials = $creds      
		#Credentials Option 2  
		#service.UseDefaultCredentials = $true  
		 #$service.TraceEnabled = $true
		## Choose to ignore any SSL Warning issues caused by Self Signed Certificates  
		  
		## Code From http://poshcode.org/624
		## Create a compilation environment
		$Provider=New-Object Microsoft.CSharp.CSharpCodeProvider
		$Compiler=$Provider.CreateCompiler()
		$Params=New-Object System.CodeDom.Compiler.CompilerParameters
		$Params.GenerateExecutable=$False
		$Params.GenerateInMemory=$True
		$Params.IncludeDebugInformation=$False
		$Params.ReferencedAssemblies.Add("System.DLL") | Out-Null

$TASource=@'
  namespace Local.ToolkitExtensions.Net.CertificatePolicy{
    public class TrustAll : System.Net.ICertificatePolicy {
      public TrustAll() { 
      }
      public bool CheckValidationResult(System.Net.ServicePoint sp,
        System.Security.Cryptography.X509Certificates.X509Certificate cert, 
        System.Net.WebRequest req, int problem) {
        return true;
      }
    }
  }
'@ 
		$TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
		$TAAssembly=$TAResults.CompiledAssembly

		## We now create an instance of the TrustAll and attach it to the ServicePointManager
		$TrustAll=$TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
		[System.Net.ServicePointManager]::CertificatePolicy=$TrustAll

		## end code from http://poshcode.org/624
		  
		## Set the URL of the CAS (Client Access Server) to use two options are availbe to use Autodiscover to find the CAS URL or Hardcode the CAS to use  
		  
		#CAS URL Option 1 Autodiscover  
		$service.AutodiscoverUrl($MailboxName,{$true})  
		"Using CAS Server : " + $Service.url   
		   
		#CAS URL Option 2 Hardcoded  
		  
		#$uri=[system.URI] "https://casservername/ews/exchange.asmx"  
		#$service.Url = $uri    
		  
		## Optional section for Exchange Impersonation  
		  
		#$service.ImpersonatedUserId = new-object Microsoft.Exchange.WebServices.Data.ImpersonatedUserId([Microsoft.Exchange.WebServices.Data.ConnectingIdType]::SmtpAddress, $MailboxName) 
		# Bind to Deleted Items Folder
		$folderid= new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::DeletedItems,$MailboxName)   
		$DeletedItems = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($service,$folderid)
		#Define ItemView to retrive just 1000 Items    
		$ivItemView =  New-Object Microsoft.Exchange.WebServices.Data.ItemView(1000) 
		$PR_RETENTION_DATE = New-Object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(0x301C,[Microsoft.Exchange.WebServices.Data.MapiPropertyType]::SystemTime); 
		$ItemPropset= new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
		$ItemPropset.Add($PR_RETENTION_DATE);
		$ivItemView.PropertySet = $ItemPropset
		$rptCollection = @{}
		$fiItems = $null    
		do{    
		    $fiItems = $service.FindItems($DeletedItems.Id,$ivItemView)    
		    #[Void]$service.LoadPropertiesForItems($fiItems,$psPropset)  
		    foreach($Item in $fiItems.Items){      
				#Process Item
				if($rptCollection.Contains($Item.ItemClass) -eq $false){
					$rptObj = "" | Select ItemClass,NumberOfItems,SizeOfItems,OldestItem,NewestItem,RetentionExpire7,RetentionExpire7To14,RetentionExpire14To30,RetentionExpire30Plus,NoRetention
					$rptObj.OldestItem = $Item.datetimereceived
					$rptObj.NewestItem = $Item.datetimereceived
					$rptObj.ItemClass = $Item.ItemClass
					$rptObj.NumberOfItems = 1
					$rptObj.SizeOfItems = $Item.Size
					$rptObj.RetentionExpire7 = 0
					$rptObj.RetentionExpire7To14 = 0
					$rptObj.RetentionExpire14To30 = 0
					$rptObj.RetentionExpire30Plus = 0
					$rptObj.NoRetention = 0
					$RetvalObj = $null
					if($Item.TryGetProperty($PR_RETENTION_DATE,[ref]$RetvalObj)){
						$rDays = ($RetvalObj - (Get-Date)).Days
						if($rDays -le 7){
							$rptObj.RetentionExpire7++
						}
						if($rDays -gt 7 -band $rDays -le 14 ){
							$rptObj.RetentionExpire7To14++
						}
						if($rDays -gt 14 -band $rDays -le 30 ){
							$rptObj.RetentionExpire14To30++
						}
						if($rDays -gt 30){
							$rptObj.RetentionExpire30Plus++
						}
					}
					else{
						$rptObj.NoRetention++
					}
					$rptCollection.Add($Item.ItemClass,$rptObj)
				}
				else{
					if($Item.datetimereceived -ne $null){
						if($Item.datetimereceived -gt $rptObj.NewestItem){
							$rptObj.NewestItem = $Item.datetimereceived
						}
						if($Item.datetimereceived -lt $rptObj.OldestItem){
							$rptObj.OldestItem = $Item.datetimereceived
						}
					}
					$RetvalObj = $null
					if($Item.TryGetProperty($PR_RETENTION_DATE,[ref]$RetvalObj)){
						$rDays = ($RetvalObj - (Get-Date)).Days
						if($rDays -le 7){
							$rptCollection[$Item.ItemClass].RetentionExpire7++
						}
						if($rDays -gt 7 -band $rDays -le 14 ){
							$rptCollection[$Item.ItemClass].RetentionExpire7To14++
						}
						if($rDays -gt 14 -band $rDays -le 30 ){
							$rptCollection[$Item.ItemClass].RetentionExpire14To30++
						}
						if($rDays -gt 30){
							$rptCollection[$Item.ItemClass].RetentionExpire30Plus++
						}
					}
					else{
						$rptCollection[$Item.ItemClass].NoRetention++
					}
					$rptCollection[$Item.ItemClass].NumberOfItems += 1
					$rptCollection[$Item.ItemClass].SizeOfItems += $Item.Size
				}
		    }    
		    $ivItemView.Offset += $fiItems.Items.Count    
		}while($fiItems.MoreAvailable -eq $true) 	
		$rptCollection.Values | Export-Csv -NoTypeInformation -Path $ReportFileName
		Write-Output $rptCollection.Values
		}
}