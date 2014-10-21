require 'spec_helper'

#def createTarget
#  # create target, and fill out the form on /customers/new
#  Target.create(name: 'TestTarget', configuration: 'a=b')
#end


def createCustomer(customerName = "ExampleCustomer" )      
  # add and provision customer "ExampleCustomer with target = TestTarget"
  fillFormForNewCustomer(customerName)
  click_button 'Save', match: :first 
end

def fillFormForNewCustomer(customerName = "ExampleCustomer" )
  if Target.where(name: 'TestTarget').count == 0
    Target.create(name: 'TestTarget', configuration: 'a=b')
  end
  visit new_customer_path # for refreshing after creating the target
  fill_in "Name",         with: customerName        
  select "TestTarget", :from => "customer[target_id]"
  
  # Note: select "TestTarget" selects the <option value=_whatever_>TestTarget</option> in the following select part of the HTML page:
  # Expected drop down in HTML page:
          #    <select id="customer_target_id" name="customer[target_id]">
          #    <option value="">Select a Target</option>
          #    <option value="2">TestTarget</option></select>
end

def destroyCustomer(customerName = "ExampleCustomer" )
  # for test: create the customer, if it does not exist:
  Delayed::Worker.delay_jobs = true
  createCustomer
  
  # de-provision the customer, if it exists on the target system
  # else delete the customer from the database
  customers = Customer.where(name: customerName)
  #p @customers[0].inspect
  unless customers[0].nil?
    Delayed::Worker.delay_jobs = false
    visit customer_path(customers[0])
    click_link "Destroy", match: :first
    Delayed::Worker.delay_jobs = true
  end
  
  # delete the customer from the database if it still exists
  customers = Customer.where(name: customerName)
  unless customers[0].nil?
    Delayed::Worker.delay_jobs = false
    visit customer_path(customers[0])
    click_link "Destroy", match: :first
    Delayed::Worker.delay_jobs = true
  end
end

describe "Customers" do
  #before { debugger }
  describe "index" do
    before { visit customers_path }   
    subject { page }
    
    it "should have the header 'Customers'" do
      expect(page).to have_selector('h2', text: 'Customers')
    end
    
    it "should have link to 'New Customer'" do     
      expect(page).to have_link( 'New Customer', href: new_customer_path )
    end
    
    its "link to 'New Customer' leads to correct page" do
      click_link "New Customer"
      expect(page).to have_selector('h2', text: 'New Customer')    
    end
    
  end # of describe "index" do
  
  describe "New Customer" do
    before { 
      # TODO: de-provision and delete customer, if it exists already
      destroyCustomer
      visit new_customer_path }
    
    it "should have the header 'New Customer'" do
      expect(page).to have_selector('h2', text: 'New Customer')
    end
    
    its "Cancel button in the left menue leads to the Customers index page" do
      click_link("Cancel", match: :first)
      expect(page).to have_selector('h2', text: 'Customers')    
    end
    
    its "Cancel button in the web form leads to the Customers index page" do
      #find html tag with class=index. Within this tag, find and click link 'Cancel' 
      first('.index').click_link('Cancel')
      expect(page).to have_selector('h2', text: 'Customers')    
    end
  end # of describe "New Customer" do
    
  describe "Create Customer" do
    before { visit new_customer_path }
    let(:submit) { "Save" }

    describe "with invalid information" do
      it "should not create a customer" do
        expect { click_button submit, match: :first }.not_to change(Customer, :count)
      end
      
      it "should not create a customer on second 'Save' button" do
        expect { first('.index').click_button submit, match: :first }.not_to change(Customer, :count)
      end
      
      describe "with duplicate name" do
        it "should not create a customer" do
          #createTarget
          createCustomer
          expect { createCustomer }.not_to change(Customer, :count)       
        end
      end
      
      # TODO: activate the test below and then implement https://www.railstutorial.org/book/_single-page#sec-uniqueness_validation 
      #describe "with case-insensitive duplicate name" do
      #  it "should not create a customer" do
      #    #createTarget
      #    customerName = "CCCCust"
      #    createCustomer customerName
      #    expect { createCustomer customerName.to_lower }.not_to change(Customer, :count)       
      #  end
      #end
    end
    
    
    describe "with valid information" do
      # does not work yet (is just ignored):
      #let(:target) { FactoryGirls.create(:target) }
      before do
        #createTarget
        fillFormForNewCustomer
      end
      
      it "should create a customer (1st 'Save' button)" do
        expect { click_button submit, match: :first }.to change(Customer, :count).by(1)       
      end
      
      it "should create a customer (2nd 'Save' button)" do
        expect { first('.index').click_button submit, match: :first }.to change(Customer, :count).by(1)
      end
      
      it "should create a customer with status 'provisioning success'" do
        # synchronous operation, so we will get deterministic test results:         
        Delayed::Worker.delay_jobs = false
        
        # TODO: should redirect to customer_path(created_customer_id)
        click_button submit, match: :first
        # for debugging:
        #p page.html.gsub(/[\n\t]/, '')
        
        # redirected page should show provisioning success
        expect(page.html.gsub(/[\n\t]/, '')).to match(/provisioning success/) #have_selector('h2', text: 'Customers')
        
        # /customers/<id> should show provisioning success
        customers = Customer.where(name: "ExampleCustomer" )
        visit customer_path(customers[0])
        # for debugging:
        #p page.html.gsub(/[\n\t]/, '')
        page.html.gsub(/[\n\t]/, '').should match(/provisioning success/)
               
      end
      
      
      it "should create a provisioning task" do
        expect { click_button submit, match: :first }.to change(Provisioning, :count).by(1)         
      end
      
      it "should create a provisioning task (2nd 'Save' button)" do
        expect { first('.index').click_button submit, match: :first }.to change(Provisioning, :count).by(1)         
      end
      
      it "should create a provisioning task with action='action=Add Customer' and 'customerName=ExampleCustomer'" do
        click_button submit, match: :first
        createdProvisioningTask = Provisioning.find(Provisioning.last)
        createdProvisioningTask.action.should match(/action=Add Customer/)
        createdProvisioningTask.action.should match(/customerName=ExampleCustomer/)
      end
      
      it "should create a provisioning task that finishes successfully or throws an Error 'Customer exists already'" do
        Delayed::Worker.delay_jobs = false
        click_button submit, match: :first
        createdProvisioningTask = Provisioning.find(Provisioning.last)
        begin
          createdProvisioningTask.status.should match(/finished successfully/)
        rescue
          createdProvisioningTask.status.should match(/Customer exists already/)          
        end
        
      end  
      
    end # of describe "with valid information" do
    
  end # of describe "Create Customer" do
    
  describe "Destroy Customer" do
    describe "De-Provision Customer" do
      before {
        # synchronous hancdling to make test results more deterministic
        Delayed::Worker.delay_jobs = false
        #createTarget
        createCustomer
        Delayed::Worker.delay_jobs = true
        
        customers = Customer.where(name: "ExampleCustomer" )            
        visit customer_path(customers[0])
        #p page.html.gsub(/[\n\t]/, '')
       
       }
         
      let(:submit) { "Delete Customer" }
      let(:submit2) { "Destroy" }
      
      # TODO: add destroy use cases
        # De-Provisioning of customer
        # Deletion of customer from database
      it "should delete a customer with status 'deletion success'" do
        # synchronous operation, so we will get deterministic test results:         
        Delayed::Worker.delay_jobs = false
        
        click_link submit, match: :first
        expect(page.html.gsub(/[\n\t]/, '')).to match(/deletion success/) #have_selector('h2', text: 'Customers')
        
        # /customers/<id> should show provisioning success
        customers = Customer.where(name: "ExampleCustomer" )
        p customers
        visit customer_path(customers[0])
        # for debugging:
        #p page.html.gsub(/[\n\t]/, '')
        page.html.gsub(/[\n\t]/, '').should match(/deletion success/)      
      end
    end # of describe "De-Provision Customer" do
    
    describe "Delete Customer from database" do
      
      before {
        # setting Delayed::Worker.delay_jobs = true causes the provisioning task not to be executed (assumption: rake jobs:work task is not started for the test enviroment)
        Delayed::Worker.delay_jobs = true
        #createTarget
        createCustomer("nonProvisionedCust")
        customers = Customer.where(name: "nonProvisionedCust" )
        visit customer_path(customers[0])

        #p page.html.gsub(/[\n\t]/, '')       
       }
         
      let(:submit) { "Delete Customer" }
      let(:submit2) { "Destroy" }
      
      it "should remove a customer from the database, if not found on the target system" do
        Delayed::Worker.delay_jobs = false # to make sure the target system is checked for the customer       
        expect { click_link submit, match: :first }.to change(Customer, :count).by(-1)
      
      end
      
    end # of describe "Delete Customer from database" do
  
  end # of describe "Destroy Customer" do
    
end # describe "Customers" do