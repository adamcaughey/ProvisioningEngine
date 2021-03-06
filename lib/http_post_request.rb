class HttpPostRequest
  def perform(headerInput, uriString=ENV["PROVISIONINGENGINE_CAMEL_URL"], httpreadtimeout=4*3600, httpopentimeout=6)
    #
    # renders headerInput="param1=value1, param2=value2, ..." and sends a HTTP POST request to uriString (default: "http://localhost/CloudWebPortal")
    #  
    verbose = true
    
    if ENV["WEBPORTAL_SIMULATION_MODE"] == "true"
      simulationMode = true
    else 
      simulationMode = false
    end

    require "net/http"
    require "uri"
    
    uri = URI.parse(uriString)
    
    #response = Net::HTTP.post_form(uri, {"testMode" => "testMode", "offlineMode" => "offlineMode", "headerInput" => "Add Customer", "customerName" => @customer.name})
    #OV replaced by (since I want to control the timers):
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = httpopentimeout
    http.read_timeout = httpreadtimeout
    request = Net::HTTP::Post.new(uri.request_uri)
    #requestviatyphoeus = Typhoeus::Request.new("http://localhost/CloudWebPortal")

    array = headerInput.split(/,/) #.map(&:strip) #seems to lead sporadically to headerInput=Show Sites to be converted to 'Show Sites' => '' instead of 'action' => 'Show Sites' during Site synchronization
#    p '+++++++++++++++++++++++++  headerInput.split(/,/) ++++++++++++++++++++++++++++++++'
#    p array.inspect
#    p array.map(&:strip).inspect
    
    #array = array.map(&:strip)
#abort array.inspect
    
    headerHash = {}

#abort headerInput.match(/\A([^=\n]+=[^=,\n]+)([,\n]*[^=,\n]+=[^=,\n]+)*\Z/).inspect
#abort headerInput.is_a?(String).inspect
#abort (!!headerInput.match(/\A([^=\n]+=[^=,\n]+)([,\n]*[^=,\n]+=[^=,\n]+)*\Z/)).inspect
    
    if headerInput.is_a?(Hash)    
      headerHash = headerInput
    #elsif headerInput.is_a?(String) && headerInput.match(/\A([^=\n]+=[^=,\n]+)([,\n]*[^=,\n]+=[^=,\n]+)*\Z/)
    elsif headerInput.is_a?(String) && headerInput.match(/\A([^=\n]+=[^=,\n]*)([,\n]*[^=,\n]+=[^=,\n]*)*\Z/)
  
      while array[0]
        variableValuePairArray = array.shift.split(/=/).map(&:strip)
            #p '+++++++++++++++++++++++++  variableValuePairArray ++++++++++++++++++++++++++++++++'
            #p variableValuePairArray.inspect
        if variableValuePairArray.length.to_s[/^2$/]
          headerHash[variableValuePairArray[0]] = variableValuePairArray[1]
        elsif variableValuePairArray.length.to_s[/^1$/]
          headerHash[variableValuePairArray[0]] = ""
        else
          abort "headerInput (here: #{headerInput}) must be of the format \"variable1=value1,variable2=value2, ...\""
        end
      end
    else
      abort "HttpPostRequest: wrong headerInput (#{headerInput.inspect}) type or format"
    end # if headerInput.is_a?(Hash)

    if simulationMode
      simulationLogString = "(simlulated) "
    else
      simulationLogString = ""
    end


    p "------------- HttpPostRequest POST Data to #{uriString} #{simulationLogString}-----------------"
    p headerHash.inspect
    p '----------------------------------------------------------'

    request.set_form_data(headerHash)

    # flash does not work in this environment:
    #flash[:notice]  = "Sent HTTP POST Data to #{uriString} #{simulationLogString}"

    if simulationMode
      
      @headerHash = headerHash
      
      # {target: "myTargetNyme"}
      def targetID(myheaderHash = @headerHash)
        {target: myheaderHash["OSVIP"]} #.match(/OSVIP.*[,&]/)
      end
      
#abort target.inspect
      
      # return {target: "myTargetNyme", customer: "myCustomerName"}
      def customerID(myheaderHash = @headerHash)
              #abort myheaderHash.inspect
        returnValue = targetID(myheaderHash)
        returnValue[:customer] = myheaderHash["customerName"]
        returnValue
      end      
            #abort customerID.inspect
      
      # return {target: "myTargetNyme", customer: "myCustomerName", site: "mySiteName"}
      def siteID(myheaderHash = @headerHash)
        return nil if myheaderHash["SiteName"].nil?
        returnValue = customerID(myheaderHash)
        returnValue[:site] = myheaderHash["SiteName"]
        returnValue
      end
      
      
      # return {user: "4989700720800"}
      def userID(myheaderHash = @headerHash)
        return nil if myheaderHash["X"].nil?
        
        # in case of :read, target, customer and site are not known. Instead, CC, AC and LOC can be sent as variables in the headerHash:
        unless myheaderHash["CC"].nil? || myheaderHash["AC"].nil? || myheaderHash["LOC"].nil? || myheaderHash["X"].nil?
          returnValue = {}
          returnValue[:user] = myheaderHash["CC"] + myheaderHash["AC"] + myheaderHash["LOC"] + myheaderHash["X"]
          return returnValue
        end
        
        # in case of :create and :delete, target, customer and site are not known, but CC, AC. LOC are not known:        
        #abort myheaderHash.inspect
        returnValue = siteID(myheaderHash)
        return nil if returnValue.nil?

        # find CC, AC, LOC from site:
        myTargets = Target.where("configuration LIKE ?", "%OSVIP%=%#{returnValue[:target]}%" )
        if myTargets.count == 1
          myTargetID = myTargets[0].id
        else
          abort "HttpPostRequest: Cannot determine target with OSVIP = #{returnValue[:target]} in the database while trying to access user with extension = #{myheaderHash['X']}"
        end
        myCustomers = Customer.where(target: myTargetID, name: returnValue[:customer])
        if myCustomers.count == 1
          myCustomerID = myCustomers[0].id
        else
          abort "HttpPostRequest: Cannot determine customer with targetID=#{myTargetID} and name=#{returnValue[:customer]} the database while trying to access user with extension = #{myheaderHash['X']}"
        end
        #myCustomerID = Customer.where(target: myTargetID, name: returnValue[:customer])[0].id
        mySites = Site.where(customer: myCustomerID, name: returnValue[:site])
        if mySites.count == 1
          mySite = mySites[0]
        else
          abort "HttpPostRequest: Cannot determine site with customerID=#{myCustomerID} and name=#{returnValue[:site]} the database while trying to access user with extension = #{myheaderHash['X']}"
        end
        
        # re-initialize the returnValue, since target, customer and site is not needed, but we will return the full DN instead
        returnValue = {}

        returnValue[:user] = mySite["countrycode"] + mySite["areacode"] + mySite["localofficecode"] + myheaderHash["X"]
        return returnValue
        
      end
      
      # quick and dirty for synchronizeAll rspec tests:
      myUserID = userID
      myUserID = {:user => "4999700730800"} if myUserID.nil?
  
      @@provisioned = {} unless defined?(@@provisioned)
      
      # if the Web server was newly started, it might have forgotten the status of the customer.
      def myTargets
        return [] if targetID.nil?
              #abort targetID.inspect
        myTargets = Target.where("configuration LIKE ?", "%OSVIP%=%#{targetID[:target]}%" ).map{|i| i}
              #abort myTargets.inspect
      end
      
      #abort myTargets.inspect
      #abort @@provisioned.inspect
      
      def syncMyCustomersFromDB        
        myTargets.each do |target|
          myCustomers = Customer.where(name: customerID[:customer], target_id: target.id)
          myCustomers.each do |customer|
            #abort @@provisioned[customerID].inspect
            #abort customer.provisioned?.inspect
            if @@provisioned[customerID].nil? # only update, if the status is not known from provisioning history (i.e. if @@provisioned[customerID] is nil)                         
              @@provisioned[customerID] = customer.provisioned? if @@provisioned[customerID].nil?
              @@provisioned[customerID] = true if /deletion in progress|waiting for deletion|de-provisioning in progress|waiting for de-provisioning/.match(customer.status)
            end
          end
        end
      end
      
      def syncMySitesFromDB        
        myTargets.each do |target|
          myCustomers = Customer.where(name: customerID[:customer], target_id: target.id)
          myCustomers.each do |customer|
            mySites = Site.where(name: siteID[:site])
            mySites.each do |site|
              if @@provisioned[siteID].nil? # only update, if the status is not known from provisioning history (i.e. if @@provisioned[siteID] is nil)             
                @@provisioned[siteID] = site.provisioned? if @@provisioned[siteID].nil?
                @@provisioned[siteID] = true if /deletion in progress|waiting for deletion|de-provisioning in progress|waiting for de-provisioning/.match(site.status)
              end
            end
          end
        end
      end
      
      def syncMyUsersFromDB        
        myTargets.each do |target|
                #abort target.inspect
                #abort customerID.inspect
          if customerID.nil? || customerID[:customer].nil?
            myCustomers = Customer.where(target_id: target.id) # since I might not know the customer for input like {"action"=>"List Users", "X"=>"2221", "CC"=>"49", "AC"=>"99", "LOC"=>"7007", "OSVIP"=>"1.2.3.4"}, we need to search the user everywhere
          else 
            myCustomers = Customer.where(name: customerID[:customer], target_id: target.id)
          end
                  #abort customerID[:customer].inspect
                #abort myCustomers.inspect
          myCustomers.each do |customer|
                  #abort customer.inspect
            if siteID.nil? || siteID[:site].nil?
              mySites = Site.where(customer_id: customer.id).map{|i| i}
              #abort mySites.inspect unless mySites.count==0
              
            else
              mySites = Site.where(customer_id: customer.id, name: siteID[:site]).map{|i| i}
            end
            mySites.each do |site|
              #abort (/#{site.countrycode}#{site.areacode}#{site.localofficecode}.{#{site.extensionlength}}/.match("498934512345")).inspect
              matches = /\A#{site.countrycode}#{site.areacode}#{site.localofficecode}.{#{site.extensionlength}}\Z/.match(userID[:user])
              #matches = /#{site.countrycode}#{site.areacode}#{site.localofficecode}.{4}/.match(userID[:user])
              
              #abort /.{#{site.extensionlength}}/.inspect unless matches.nil?
              #abort matches.inspect unless matches.nil?
              myExtension = userID[:user].gsub("#{site.countrycode}#{site.areacode}#{site.localofficecode}",'') unless matches.nil?
              #abort myExtension.inspect unless matches.nil?
              #abort site.id.inspect unless matches.nil?
              myUsers = User.where(site_id: site.id, extension: myExtension) unless matches.nil?
              #abort myUser.inspect unless myUser.nil? || myUser.count == 0 
              myUsers.each do |user|
                #abort user.inspect
                #abort @@provisioned[userID].inspect
                p @@provisioned[userID].inspect
                p user.inspect
                p user.provisioned?.inspect
                if @@provisioned[userID].nil? # only update, if the status is not known from provisioning history (i.e. if @@provisioned[userID] is nil)
                  @@provisioned[userID] = user.provisioned? if 
                  # override: is still provisioned in the following cases:
                  @@provisioned[userID] = true if @@provisioned[userID].nil? && /deletion in progress|waiting for deletion|de-provisioning in progress|waiting for de-provisioning/.match(user.status)
                end
                #abort @@provisioned[userID].inspect
                p @@provisioned[userID].inspect
                p user.inspect
                p user.provisioned?.inspect
              end unless myUsers.nil?
              
              myUsers = nil

            end
          end
        end
      end
      
      if verbose
        p "customerID = #{customerID}"
        p "siteID = #{siteID}"
        p "myUserID = #{myUserID.inspect}"
        p "@@provisioned[customerID] before sync: #{@@provisioned[customerID]}"
        p "@@provisioned[siteID] before sync: #{@@provisioned[siteID]}"
        p "@@provisioned[myUserID] before sync: #{@@provisioned[myUserID]}"
      end
      
      syncMyCustomersFromDB unless customerID.nil? 
      
      syncMySitesFromDB unless siteID.nil?
      
      syncMyUsersFromDB unless userID.nil?
      #abort userID.inspect
      
      
      
      #abort @@provisioned.inspect
      
      #abort myCustomers.inspect
      

      #@@provisioned[customerID] = myCustomer.provisioned? unless myCustomer.nil?

      if verbose
        p "customerID = #{customerID}"
        p "siteID = #{siteID}"
        p "myUserID = #{myUserID.inspect}"
        p "@@provisioned[customerID] after sync before provisioning: #{@@provisioned[customerID]}"
        p "@@provisioned[siteID] after sync before provisioning: #{@@provisioned[siteID]}"
        p "@@provisioned[myUserID] after sync before provisioning: #{@@provisioned[myUserID]}"
      end
 
      sleep 100.seconds / 1000
      case headerHash["action"]
        when /Add Customer/
          if @@provisioned[customerID].nil? || !@@provisioned[customerID]
            responseBody = "Success: 234     Errors:0     Syntax Errors:0"
            @@provisioned[customerID] = true #unless customerID.nil?
            #abort @@provisioned.inspect
            #@@customerprovisioned = true
          else 
            @@provisioned[customerID] = true #unless customerID.nil?
            responseBody = 'ERROR: java.lang.Exception: Cannot Create customer ExampleCustomerV8: Customer exists already!'
          end
        when /Add Site/
          if @@provisioned[siteID].nil? || !@@provisioned[siteID]
            responseBody = "Success: 234     Errors:0     Syntax Errors:0"
            @@provisioned[siteID] = true
          else
            @@provisioned[siteID] = true
            responseBody = 'ERROR: java.lang.Exception: Site Name "ExampleSite" exists already in the data base (Numbering Plan = NP_Site1_00010)!'
          end
        when /Add User/
                  #abort myUserID.inspect
                  #abort @@provisioned[myUserID].inspect
          if @@provisioned[myUserID].nil? || !@@provisioned[myUserID]
            responseBody = "Success: 234     Errors:0     Syntax Errors:0"
            @@provisioned[myUserID] = true
          else
            @@provisioned[myUserID] = true
            responseBody = 'ERROR: java.lang.Exception: Cannot create user with phone number +49 (99) 7007 30800: phone number is in use already!'
          end
                  #abort myUserID.inspect
                  #abort @@provisioned[myUserID].inspect
        when /Delete Customer/
          if @@provisioned[customerID]
            responseBody = "Success: 234     Errors:0     Syntax Errors:0"
            @@provisioned[customerID] = false
          else
            responseBody = 'ERROR: java.lang.Exception: Customer "ExampleCustomerV8" does not exist on the data base!'
            @@provisioned[customerID] = false
          end
        when /Delete Site/
          if @@provisioned[siteID]
            responseBody = "Success: 234     Errors:0     Syntax Errors:0"
            @@provisioned[siteID] = false
          else
            responseBody = 'ERROR: java.lang.Exception: Site Name "ExampleSite" does not exist in the data base!'
            @@provisioned[siteID] = false
          end
        when /Delete User/
          #abort @@provisioned[myUserID].inspect
          if @@provisioned[myUserID]
            responseBody = "Success: 234     Errors:0     Syntax Errors:0"
            @@provisioned[myUserID] = false
          else
            responseBody = 'ERROR: java.lang.Exception: Cannot delete user with phone number ' + myUserID[:user] + ': phone number does not exist for this customer!'
            @@provisioned[myUserID] = false
          end
        when /Show Sites/
          # quick and dirty for synchronizeAll rspec tests:
          mySiteID = siteID
                  #p "111111111111111111111111111" + mySiteID.inspect if verbose
                  #p "111111111111111111111111111" + mySiteID.nil?.inspect if verbose
          if mySiteID.nil?
            mySiteID = customerID
            mySiteID[:site] = "ExampleSite"
                  #p "222222222222222222222222222" + mySiteID.inspect if verbose
          end
                  #p "333333333333333333333333333" + mySiteID.inspect if verbose
                  #p @@provisioned.inspect if verbose
                  #p "44444444444444444444444444 @@provisioned[mySiteID] = " + @@provisioned[mySiteID].inspect if verbose
                  #p "5555555555555555555555555 siteID[:customer] = " + mySiteID[:customer].inspect if verbose
                  #p "6666666666666666666666666 siteID[:site] = " + mySiteID[:customer].inspect if verbose

          if @@provisioned[mySiteID] == true
            responseBody = '<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<Result>
    <ResultCode>0</ResultCode>
    <ResultText>Success</ResultText>
    <Sites>
        <Site>
            <CustomerName>' + mySiteID[:customer] + '</CustomerName>
            <SiteName>' + mySiteID[:customer] + '</SiteName>
            <NumberingPlanName>CNP_ExampleCustomerV8_00007</NumberingPlanName>
            <GatewayIP></GatewayIP>
            <MainNumber></MainNumber>
        </Site>
        <Site>
            <CustomerName>' + mySiteID[:customer] + '</CustomerName>
            <SiteName>' + mySiteID[:site] + '</SiteName>
            <NumberingPlanName>NP_' + mySiteID[:site] + '_00008</NumberingPlanName>
            <GatewayIP>47.68.190.57</GatewayIP>
            <SiteCode>99821</SiteCode>
            <CountryCode>49</CountryCode>
            <AreaCode>99</AreaCode>
            <LocalOfficeCode>7007</LocalOfficeCode>
            <ExtensionLength>5</ExtensionLength>
            <MainNumber>4999700710000</MainNumber>
        </Site>
    </Sites>
</Result>'
                  #p "7777777777777777777777777777777 responseBody = " + responseBody.inspect if verbose
            else
              responseBody = '<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<Result>
    <ResultCode>0</ResultCode>
    <ResultText>Success</ResultText>
    <Sites>
        <Site>
            <SiteName>ExampleCustomerV8</SiteName>
            <NumberingPlanName>CNP_ExampleCustomerV8_00013</NumberingPlanName>
            <GatewayIP></GatewayIP>
            <MainNumber></MainNumber>
        </Site>
    </Sites>
</Result>'
            end
        when /List Users/
          
                  #abort myUserID.inspect
                  #abort @@provisioned[myUserID].inspect
          if @@provisioned[myUserID]
            responseBody = '<Result><ServiceId>' + myUserID[:user] + '</ServiceId><ServiceId>9999999991</ServiceId><ServiceId>9999999992</ServiceId></Result>'
          else
            responseBody = '<Result><ServiceId>9999999991</ServiceId><ServiceId>9999999992</ServiceId></Result>'
          end
        when /List Customers/
                    #abort "ooooooooooooooooooooooooo" + customerID[:customer].nil?.inspect         
          if customerID[:customer].nil?
            
            # this is a List Customer with no customer specified; we need to fake the list answer
            # for now, we will only look at ExampleCustomerV7R1 and ExampleCustomerV8 needed by rspec
            # TODO: read provisioned BGs from @@provisioned, instead of only adding ExampleCustomerV7R1 and ExampleCustomerV8
            snippet = ""
            snippets = {}
            # as of today, the name ExampleCustomerV7R1 is not used, therefore commented out:
#            ['ExampleCustomerV7R1', 'ExampleCustomerV8'].each do |cust_i|
            ['ExampleCustomerV8'].each do |cust_i|  
              customerID_i = customerID
              customerID_i[:customer] = cust_i
                        #abort "ooooooooooooooooooooooooo" + customerID_i.inspect
                        #abort "ooooooooooooooooooooooooo" + @@provisioned[customerID_i].inspect
                        #abort "ooooooooooooooooooooooooo" + @@provisioned.inspect
              snippets[cust_i] = "<BGName>#{cust_i}</BGName>" if @@provisioned[customerID_i]
                        #abort "ooooooooooooooooooooooooo" + snippets.inspect              
            end
            
            snippets.each do |key, value|
              snippet = "#{snippet}#{value}"
            end
            
                        #abort "ooooooooooooooooooooooooo" + snippet
            
            responseBody = '<?xml version="1.0" encoding="UTF-8"?>
<SOAPResult><Result>Success</Result><GetBGListData><BGName>BG_DC</BGName>' + snippet + '</GetBGListData></SOAPResult>'
                        #abort "ooooooooooooooooooooooooo" + responseBody           
          elsif @@provisioned[customerID]                      
            responseBody = '<?xml version="1.0" encoding="UTF-8"?>
<SOAPResult><Result>Success</Result><GetBGListData><BGName>BG_DC</BGName><BGName>' + customerID[:customer] + '</BGName></GetBGListData></SOAPResult>'
          else
            responseBody = '<?xml version="1.0" encoding="UTF-8"?>
<SOAPResult><Result>Success</Result><GetBGListData><BGName>BG_DC</BGName></GetBGListData></SOAPResult>'
          end
        when /PrepareSystem/
          alreadyProvisioned = true
          case alreadyProvisioned
            when true # case alreadyProvisioned
              responseBody = '<pre>###################################
# OSV_VR
###################################
###################################
# OSV_VR
###################################
Allow SSH password authentication (needed by Apache Camel SSH module) ...&quot; &amp;&amp; grep -q &quot;PasswordAuthentication no&quot; /etc/ssh/sshd_config &amp;&amp; appendix=.camel.bak_`date +%F--%s` &amp;&amp; cp -p /etc/ssh/sshd_config /etc/ssh/sshd_config$appendix &amp;&amp; sed &quot;s/PasswordAuthentication no/PasswordAuthentication yes/&quot; /etc/ssh/sshd_config$appendix &gt; /etc/ssh/sshd_config &amp;&amp; /etc/init.d/sshd restart &amp;&amp; echo &quot;PrepareOSVSSH: added password authentication support...&quot; || echo &quot;PrepareOSVSSH: password authentication is already supported: nothing to do...&quot; )
whoami | grep -q Preparing srx access from the ProvisioningEngine...&quot; &amp;&amp; grep &quot;\-\:srx&quot; /etc/security/access.conf | grep  -v -q &quot;192.168.113.104&quot; &amp;&amp; appendix=.camel.bak_`date +%F--%s` &amp;&amp; cp -p /etc/security/access.conf /etc/security/access.conf$appendix &amp;&amp; sed &quot;s/\(\-\:srx.*LOCAL\)/\1 192.168.113.104 /&quot; /etc/security/access.conf$appendix &gt; /etc/security/access.conf &amp;&amp; echo &quot;PrepareOSVSSH: added Web Portal to the list of allowed srx ssh hosts&quot; || echo &quot;PrepareOSVSSH: Web Portal already allowed: nothing to do&quot; )
whoami | grep 
###################################
# OSV_VR
###################################
version of existing ProvisioningScripts = 0.4.7.2
version of new ProvisioningScripts = 0.4.7.2
Existing ProvisioningScripts do not need to be upgraded. Exiting...

###################################
# OSV_VR
###################################
running batch file...
headers.batchFileName = batchFile-31607548.sh
sh batchFile-31607548.sh &gt; batchFile-31607548.sh.out
Nothing to do: Packet Filter Rule &quot;SOAP_permit_192.168.113.104&quot; exists already
Nothing to do: Packet Filter Rule &quot;SPML_permit_192.168.113.104&quot; exists already
finished execution of batch file batchFile-31607548.sh

###################################
# OSV_VR
###################################

###################################
# OSV_VR
###################################


###################################
# XPR_V7: XPR Provisioning not supported for action=PrepareSystem
###################################

###################################
# UC_V: UC Provisioning not supported for action=PrepareSystem
###################################

</pre>'
            when false # case alreadyProvisioned
              responseBody ='<pre>###################################
# OSV_VR
###################################
###################################
# OSV_VR
###################################
Allow SSH password authentication (needed by Apache Camel SSH module) ...&quot; &amp;&amp; grep -q &quot;PasswordAuthentication no&quot; /etc/ssh/sshd_config &amp;&amp; appendix=.camel.bak_`date +%F--%s` &amp;&amp; cp -p /etc/ssh/sshd_config /etc/ssh/sshd_config$appendix &amp;&amp; sed &quot;s/PasswordAuthentication no/PasswordAuthentication yes/&quot; /etc/ssh/sshd_config$appendix &gt; /etc/ssh/sshd_config &amp;&amp; /etc/init.d/sshd restart &amp;&amp; echo &quot;PrepareOSVSSH: added password authentication support...&quot; || echo &quot;PrepareOSVSSH: password authentication is already supported: nothing to do...&quot; )
whoami | grep -q Preparing srx access from the ProvisioningEngine...&quot; &amp;&amp; grep &quot;\-\:srx&quot; /etc/security/access.conf | grep  -v -q &quot;192.168.113.104&quot; &amp;&amp; appendix=.camel.bak_`date +%F--%s` &amp;&amp; cp -p /etc/security/access.conf /etc/security/access.conf$appendix &amp;&amp; sed &quot;s/\(\-\:srx.*LOCAL\)/\1 192.168.113.104 /&quot; /etc/security/access.conf$appendix &gt; /etc/security/access.conf &amp;&amp; echo &quot;PrepareOSVSSH: added Web Portal to the list of allowed srx ssh hosts&quot; || echo &quot;PrepareOSVSSH: Web Portal already allowed: nothing to do&quot; )
whoami | grep 
###################################
# OSV_VR
###################################
folder ProvisioningScripts does not exist yet. It will be created now.
version of new ProvisioningScripts = 0.4.7.2
found new ProvisioningScripts version: starting to extract ProvisioningScripts.tar.gz, overwriting existing files...
ProvisioningScripts/
ProvisioningScripts/ccc.sh
ProvisioningScripts/ccc_variables_examples.txt
ProvisioningScripts/chsettings.sh
ProvisioningScripts/delete.awk
ProvisioningScripts/delete.sh
ProvisioningScripts/delete_variables.txt
ProvisioningScripts/export.sh
ProvisioningScripts/findAndReplaceTools
ProvisioningScripts/modules/
ProvisioningScripts/modules/ccc_MI_Feature_01_ServiceCodeXprUC.sh
ProvisioningScripts/modules/ccc_MI_Fixes_01_CQ00270348_Alias.sh
ProvisioningScripts/modules/ccc_MI_Fixes_02_DeleteIntercepts.sh
ProvisioningScripts/modules/ccc_MT_Base_01_DeletedCommands.sh
ProvisioningScripts/modules/ccc_MT_Base_02_Renaming.sh
ProvisioningScripts/modules/ccc_MT_Base_03_UCMediaserver.sh
ProvisioningScripts/modules/ccc_MT_Base_04_Xpressions.sh
ProvisioningScripts/modules/ccc_MT_Base_05_CentralGateway.sh
ProvisioningScripts/modules/ccc_MT_Base_06_DNM.sh
ProvisioningScripts/modules/ccc_MT_Base_07_OfficeCode.sh
ProvisioningScripts/modules/ccc_MT_Base_08_RemainingChanges.sh
ProvisioningScripts/modules/ccc_MT_Feature_01_ServiceCodeXprUC.sh
ProvisioningScripts/modules/ccc_MT_Fixes_01_DeltaProblems.sh
ProvisioningScripts/modules/ccc_MT_FI_01_DeletedCommands.sh
ProvisioningScripts/modules/ccc_MT_FI_02_Renaming.sh
ProvisioningScripts/modules/ccc_MT_FI_03_UCMediaserver.sh
ProvisioningScripts/modules/ccc_MT_FI_04_Xpressions.sh
ProvisioningScripts/modules/ccc_MT_FI_05_CentralGateway.sh
ProvisioningScripts/modules/ccc_MT_FI_06_OSVMediaserver.sh
ProvisioningScripts/modules/ccc_MT_FI_07_APAC_DestCode.sh
ProvisioningScripts/modules/ccc_MT_FI_Fixes_01_DeleteIntercepts.sh
ProvisioningScripts/modules/exec_MT_FI/
ProvisioningScripts/modules/exec_MT_FI/S011_ccc_MT_FI_01_DeletedCommands
ProvisioningScripts/modules/exec_MT_FI/S012_ccc_MT_FI_02_Renaming
ProvisioningScripts/modules/exec_MT_FI/S013_ccc_MT_FI_03_UCMediaserver
ProvisioningScripts/modules/exec_MT_FI/S014_ccc_MT_FI_04_Xpressions
ProvisioningScripts/modules/exec_MT_FI/S015_ccc_MT_FI_05_CentralGateway
ProvisioningScripts/modules/exec_MT_FI/S016_ccc_MT_FI_06_DNM
ProvisioningScripts/modules/exec_MT_FI/S017_ccc_MT_FI_07_OSVMediaserver
ProvisioningScripts/modules/exec_MT_FI/S018_ccc_MT_FI_08_APAC_DestCode
ProvisioningScripts/modules/exec_MT/
ProvisioningScripts/modules/exec_MT/S011_ccc_MT_Base_01_DeletedCommands
ProvisioningScripts/modules/exec_MT/S012_ccc_MT_Base_02_Renaming
ProvisioningScripts/modules/exec_MT/S013_ccc_MT_Base_03_UCMediaserver
ProvisioningScripts/modules/exec_MT/S014_ccc_MT_Base_04_Xpressions
ProvisioningScripts/modules/exec_MT/S015_ccc_MT_Base_05_CentralGateway
ProvisioningScripts/modules/exec_MT/S016_ccc_MT_Base_06_DNM
ProvisioningScripts/modules/exec_MT/S017_ccc_MT_Base_07_OfficeCode
ProvisioningScripts/modules/exec_MT/S018_ccc_MT_Base_08_RemainingChanges
ProvisioningScripts/modules/exec_MT/S051_ccc_MT_Feature_01_ServiceCodeXprUC
ProvisioningScripts/modules/exec_MT/S101_ccc_MT_Fixes_01_DeltaProblems
ProvisioningScripts/modules/exec_MT/S102_ccc_MT_Fixes_02_DNM_CQ00305443
ProvisioningScripts/modules/exec_MT/S000_ccc_all_00_DeleteFeatureProfiles.sh
ProvisioningScripts/modules/exec_MI/
ProvisioningScripts/modules/exec_MI/S051_ccc_MI_Feature_01_ServiceCodeXprUC
ProvisioningScripts/modules/exec_MI/S101_ccc_MI_Fixes_01_CQ00270348_Alias
ProvisioningScripts/modules/exec_MI/S102_ccc_MI_Fixes_02_DeleteIntercepts
ProvisioningScripts/modules/ccc_MT_Base_00_DeleteFeatureProfiles.sh
ProvisioningScripts/modules/ccc_all_00_DeleteFeatureProfiles.sh
ProvisioningScripts/modules/ccc_MT_FI_06_DNM.sh
ProvisioningScripts/modules/ccc_MT_FI_07_OSVMediaserver.sh
ProvisioningScripts/modules/ccc_MT_FI_08_APAC_DestCode.sh
ProvisioningScripts/modules/ccc_MT_FI_Fixes_01_DeleteIntercepts_obsolete_inV8.sh
ProvisioningScripts/modules/ccc_MT_Fixes_02_DNM_CQ00305443.sh
ProvisioningScripts/removelinebreaks.sh
ProvisioningScripts/soapCli/
ProvisioningScripts/soapCli/myCancelJob
ProvisioningScripts/soapCli/mySoapRequest
ProvisioningScripts/soapCli/myTestProcessXml
ProvisioningScripts/soapCli/soapCommon.ksh
ProvisioningScripts/soapCli/soapCli
ProvisioningScripts/soapCli/TestSendSoapReq
ProvisioningScripts/soapCli/TestSoap.ksh
ProvisioningScripts/soapCli/xml.templates
ProvisioningScripts/soapCli/TestSendSoapReq.orig
ProvisioningScripts/split_bg.awk
ProvisioningScripts/split_site.awk
ProvisioningScripts/version.txt
ProvisioningScripts/export_all.sh
ProvisioningScripts/split_feature.awk
ProvisioningScripts/FirstInitialisationOSVTemplate_V7.txt
ProvisioningScripts/FirstInitialisationOSVTemplate_V8.txt
ProvisioningScripts/soapMassProv.sh
ProvisioningScripts/openscapevoiceconfig_V8_wo_HomeDn_display_and_BGLINENAME_corrected.txt
backup.sh
restore.sh
ProvisioningScripts successfully updated

###################################
# OSV_VR
###################################
running batch file...
headers.batchFileName = batchFile-80083641.sh
sh batchFile-80083641.sh &gt; batchFile-80083641.sh.out
Packet Filter Rule &quot;SOAP_permit_192.168.113.104&quot; created. For removing, log into the OSV Linux prompt and perform su - srx -c &quot;startCli -x&quot; and then pktFltrRulesRemove &quot;SOAP_permit_192.168.113.104&quot;
Packet Filter Rule &quot;SPML_permit_192.168.113.104&quot; created. For removing, log into the OSV Linux prompt and perform su - srx -c &quot;startCli -x&quot; and then pktFltrRulesRemove &quot;SPML_permit_192.168.113.104&quot;
finished execution of batch file batchFile-80083641.sh

###################################
# OSV_VR
###################################

###################################
# OSV_VR
###################################


###################################
# XPR_V7: XPR Provisioning not supported for action=PrepareSystem
###################################

###################################
# UC_V: UC Provisioning not supported for action=PrepareSystem
###################################

</pre>'
            when 'mixed' # case alreadyProvisioned
			# from a test with OSV V7R1, where may be the Password authentication was correct or no; need to retest the Password authentication part in Camel...
              responseBody ='###################################
# OSV_VR
###################################
###################################
# OSV_VR
###################################
Allow SSH password authentication (needed by Apache Camel SSH module) ..." && grep -q "PasswordAuthentication no" /etc/ssh/sshd_config && appendix=.camel.bak_`date +%F--%s` && cp -p /etc/ssh/sshd_config /etc/ssh/sshd_config$appendix && sed "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config$appendix > /etc/ssh/sshd_config && /etc/init.d/sshd restart && echo "PrepareOSVSSH: added password authentication support..." || echo "PrepareOSVSSH: password authentication is already supported: nothing to do..." )
whoami | grep -q Preparing srx access from the ProvisioningEngine..." && grep "\-\:srx" /etc/security/access.conf | grep  -v -q "192.168.113.104" && appendix=.camel.bak_`date +%F--%s` && cp -p /etc/security/access.conf /etc/security/access.conf$appendix && sed "s/\(\-\:srx.*LOCAL\)/\1 192.168.113.104 /" /etc/security/access.conf$appendix > /etc/security/access.conf && echo "PrepareOSVSSH: added Web Portal to the list of allowed srx ssh hosts" || echo "PrepareOSVSSH: Web Portal already allowed: nothing to do" )
whoami | grep 
###################################
# OSV_VR
###################################
version of existing ProvisioningScripts = 0.4.7.2
version of new ProvisioningScripts = 0.4.7.2
Existing ProvisioningScripts do not need to be upgraded. Exiting...

###################################
# OSV_VR
###################################
running batch file...
headers.batchFileName = batchFile-93733174.sh
sh batchFile-93733174.sh > batchFile-93733174.sh.out
Nothing to do: Packet Filter Rule "SOAP_permit_192.168.113.104" exists already
Nothing to do: Packet Filter Rule "SPML_permit_192.168.113.104" exists already
finished execution of batch file batchFile-93733174.sh

###################################
# OSV_VR
###################################

###################################
# OSV_VR
###################################


###################################
# XPR_V7: XPR Provisioning not supported for action=PrepareSystem
###################################

###################################
# UC_V: UC Provisioning not supported for action=PrepareSystem
###################################'
          end # case alreadyProvisioned
        else # case headerHash["action"]
          responseBody = "HttpPostRequest.perform: action=#{headerHash["action"]} not supported in simulation mode"
      end # case headerHash["action"]

      if verbose
        p "customerID = #{customerID}"
        p "siteID = #{siteID}"
        p "myUserID = #{myUserID.inspect}"
        p "@@provisioned[customerID] after provisioning: #{@@provisioned[customerID]}"
        p "@@provisioned[siteID] after provisioning: #{@@provisioned[siteID]}"
        p "@@provisioned[myUserID] after provisioning: #{@@provisioned[myUserID]}"
      end    
                  #abort myUserID.inspect
                  #abort @@provisioned[myUserID].inspect    
    else # if simulationMode   
      begin
        response = http.request(request)
        responseBody = response.body
      rescue
        responseBody = nil
      end
    end # else # if simulationMode

    
    return responseBody
  end # def perform
end
