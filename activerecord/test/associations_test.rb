require 'abstract_unit'
require 'fixtures/developer'
require 'fixtures/project'
require 'fixtures/company'
require 'fixtures/topic'
require 'fixtures/reply'
require 'fixtures/computer'

# Can't declare new classes in test case methods, so tests before that
bad_collection_keys = false
begin
  class Car < ActiveRecord::Base; has_many :wheels, :name => "wheels"; end
rescue ActiveRecord::ActiveRecordError
  bad_collection_keys = true
end
raise "ActiveRecord should have barked on bad collection keys" unless bad_collection_keys


class AssociationsTest < Test::Unit::TestCase
  fixtures :accounts, :companies, :developers, :projects, :developers_projects,
           :computers
  
  def test_force_reload
    firm = Firm.new("name" => "A New Firm, Inc")
    firm.save
    firm.clients.each {|c|} # forcing to load all clients
    assert firm.clients.empty?, "New firm shouldn't have client objects"
    assert !firm.has_clients?, "New firm shouldn't have clients"
    assert_equal 0, firm.clients.size, "New firm should have 0 clients"

    client = Client.new("name" => "TheClient.com", "firm_id" => firm.id)
    client.save

    assert firm.clients.empty?, "New firm should have cached no client objects"
    assert !firm.has_clients?, "New firm should have cached a no-clients response"
    assert_equal 0, firm.clients.size, "New firm should have cached 0 clients count"

    assert !firm.clients(true).empty?, "New firm should have reloaded client objects"
    assert_equal 1, firm.clients(true).size, "New firm should have reloaded clients count"
  end

  def test_storing_in_pstore
    require "tmpdir"
    store_filename = File.join(Dir.tmpdir, "ar-pstore-association-test")
    File.delete(store_filename) if File.exists?(store_filename)
    require "pstore"
    apple = Firm.create("name" => "Apple")
    natural = Client.new("name" => "Natural Company")
    apple.clients << natural

    db = PStore.new(store_filename)
    db.transaction do
      db["apple"] = apple
    end

    db = PStore.new(store_filename)
    db.transaction do
      assert_equal "Natural Company", db["apple"].clients.first.name
    end
  end
end

class HasOneAssociationsTest < Test::Unit::TestCase
  fixtures :accounts, :companies, :developers, :projects, :developers_projects
  
  def test_has_one
    assert_equal companies(:first_firm).account, Account.find(1)
    assert_equal Account.find(1).credit_limit, companies(:first_firm).account.credit_limit
  end

  def test_triple_equality
    assert Account === companies(:first_firm).account
  end

  def test_type_mismatch
    assert_raises(ActiveRecord::AssociationTypeMismatch) { companies(:first_firm).account = 1 }
    assert_raises(ActiveRecord::AssociationTypeMismatch) { companies(:first_firm).account = Project.find(1) }
  end

  def test_natural_assignment
    apple = Firm.create("name" => "Apple")
    citibank = Account.create("credit_limit" => 10)
    apple.account = citibank
    assert_equal apple.id, citibank.firm_id
  end
  
  def test_natural_assignment_to_nil
    old_account_id = companies(:first_firm).account.id
    companies(:first_firm).account = nil
    companies(:first_firm).save
    assert_nil companies(:first_firm).account
    # account is dependent, therefore is destroyed when reference to owner is lost
    assert_raises(ActiveRecord::RecordNotFound) { Account.find(old_account_id) } 
  end
  
  def test_assignment_without_replacement
    apple = Firm.create("name" => "Apple")
    citibank = Account.create("credit_limit" => 10)
    apple.account = citibank
    assert_equal apple.id, citibank.firm_id
    
    hsbc = apple.build_account({ :credit_limit => 20}, false)
    assert_equal apple.id, hsbc.firm_id
    hsbc.save
    assert_equal apple.id, citibank.firm_id

    nykredit = apple.create_account({ :credit_limit => 30}, false)
    assert_equal apple.id, nykredit.firm_id
    assert_equal apple.id, citibank.firm_id
    assert_equal apple.id, hsbc.firm_id
  end

  def test_assignment_without_replacement_on_create
    apple = Firm.create("name" => "Apple")
    citibank = Account.create("credit_limit" => 10)
    apple.account = citibank
    assert_equal apple.id, citibank.firm_id
    
    hsbc = apple.create_account({:credit_limit => 10}, false)
    assert_equal apple.id, hsbc.firm_id
    hsbc.save
    assert_equal apple.id, citibank.firm_id
  end

  def test_dependence
    firm = Firm.find(1)
    assert !firm.account.nil?
    firm.destroy
    assert_equal 1, Account.find_all.length
  end

  def test_succesful_build_association
    firm = Firm.new("name" => "GlobalMegaCorp")
    firm.save

    account = firm.build_account("credit_limit" => 1000)
    assert account.save
    assert_equal account, firm.account
  end

  def test_failing_build_association
    firm = Firm.new("name" => "GlobalMegaCorp")
    firm.save

    account = firm.build_account
    assert !account.save
    assert_equal "can't be empty", account.errors.on("credit_limit")
  end

  def test_create_association
    firm = Firm.new("name" => "GlobalMegaCorp")
    firm.save
    assert_equal firm.create_account("credit_limit" => 1000), firm.account
  end

  def test_build
    firm = Firm.new("name" => "GlobalMegaCorp")
    firm.save

    firm.account = account = Account.new("credit_limit" => 1000)
    assert_equal account, firm.account
    assert account.save
    assert_equal account, firm.account
  end

  def test_build_before_child_saved
    firm = Firm.find(1)

    account = firm.account.build("credit_limit" => 1000)
    assert_equal account, firm.account
    assert account.new_record?
    assert firm.save
    assert_equal account, firm.account
    assert !account.new_record?
  end

  def test_build_before_either_saved
    firm = Firm.new("name" => "GlobalMegaCorp")

    firm.account = account = Account.new("credit_limit" => 1000)
    assert_equal account, firm.account
    assert account.new_record?
    assert firm.save
    assert_equal account, firm.account
    assert !account.new_record?
  end

  def test_failing_build_association
    firm = Firm.new("name" => "GlobalMegaCorp")
    firm.save
    
    firm.account = account = Account.new
    assert_equal account, firm.account
    assert !account.save
    assert_equal account, firm.account
    assert_equal "can't be empty", account.errors.on("credit_limit")
  end

  def test_create
    firm = Firm.new("name" => "GlobalMegaCorp")
    firm.save
    firm.account = account = Account.create("credit_limit" => 1000)
    assert_equal account, firm.account
  end

  def test_create_before_save
    firm = Firm.new("name" => "GlobalMegaCorp")
    firm.account = account = Account.create("credit_limit" => 1000)
    assert_equal account, firm.account
  end

  def test_dependence_with_missing_association
    Account.destroy_all
    firm = Firm.find(1)
    assert firm.account.nil?
    firm.destroy
  end

  def test_assignment_before_parent_saved
    firm = Firm.new("name" => "GlobalMegaCorp")
    firm.account = a = Account.find(1)
    assert firm.new_record?
    assert_equal a, firm.account
    assert firm.save
    assert_equal a, firm.account
    assert_equal a, firm.account(true)
  end

  def test_assignment_before_child_saved
    firm = Firm.find(1)
    firm.account = a = Account.new("credit_limit" => 1000)
    assert !a.new_record?
    assert_equal a, firm.account
    assert_equal a, firm.account
    assert_equal a, firm.account(true)
  end

  def test_assignment_before_either_saved
    firm = Firm.new("name" => "GlobalMegaCorp")
    firm.account = a = Account.new("credit_limit" => 1000)
    assert firm.new_record?
    assert a.new_record?
    assert_equal a, firm.account
    assert firm.save
    assert !firm.new_record?
    assert !a.new_record?
    assert_equal a, firm.account
    assert_equal a, firm.account(true)
  end
end


class HasManyAssociationsTest < Test::Unit::TestCase
  fixtures :accounts, :companies, :developers, :projects,
           :developers_projects, :topics
  
  def force_signal37_to_load_all_clients_of_firm
    companies(:first_firm).clients_of_firm.each {|f| }
  end
  
  def test_counting
    assert_equal 2, Firm.find_first.clients.count
  end
  
  def test_finding
    assert_equal 2, Firm.find_first.clients.length
  end

  def test_finding_default_orders
    assert_equal "Summit", Firm.find_first.clients.first.name
  end

  def test_finding_with_different_class_name_and_order
    assert_equal "Microsoft", Firm.find_first.clients_sorted_desc.first.name
  end

  def test_finding_with_foreign_key
    assert_equal "Microsoft", Firm.find_first.clients_of_firm.first.name
  end

  def test_finding_with_condition
    assert_equal "Microsoft", Firm.find_first.clients_like_ms.first.name
  end

  def test_finding_using_sql
    firm = Firm.find_first
    first_client = firm.clients_using_sql.first
    assert_not_nil first_client
    assert_equal "Microsoft", first_client.name
    assert_equal 1, firm.clients_using_sql.size
    assert_equal 1, Firm.find_first.clients_using_sql.size
  end

  def test_counting_using_sql
    assert_equal 1, Firm.find_first.clients_using_counter_sql.size
    assert_equal 0, Firm.find_first.clients_using_zero_counter_sql.size
  end

  def test_counting_non_existant_items_using_sql
    assert_equal 0, Firm.find_first.no_clients_using_counter_sql.size
  end
  
  def test_belongs_to_sanity
    c = Client.new
    assert_nil c.firm

    if c.firm
      assert false, "belongs_to failed if check"
    end

    unless c.firm
    else
      assert false,  "belongs_to failed unless check"
    end
        
  end

  def test_find_ids
    firm = Firm.find_first

    assert_raises(ActiveRecord::RecordNotFound) { firm.clients.find }

    client = firm.clients.find(2)
    assert_kind_of Client, client

    client_ary = firm.clients.find([2])
    assert_kind_of Array, client_ary
    assert_equal client, client_ary.first

    client_ary = firm.clients.find(2, 3)
    assert_kind_of Array, client_ary
    assert_equal 2, client_ary.size
    assert_equal client, client_ary.first

    assert_raises(ActiveRecord::RecordNotFound) { firm.clients.find(2, 99) }
  end

  def test_find_all
    firm = Firm.find_first
    assert_equal firm.clients, firm.clients.find_all
    assert_equal 2, firm.clients.find(:all, :conditions => "type = 'Client'").length
    assert_equal 1, firm.clients.find(:all, :conditions => "name = 'Summit'").length
  end

  def test_find_all_sanitized
    firm = Firm.find_first
    assert_equal firm.clients.find_all("name = 'Summit'"), firm.clients.find_all(["name = '%s'", "Summit"])
  end

  def test_find_first
    firm = Firm.find_first
    assert_equal firm.clients.first, firm.clients.find_first
    assert_equal Client.find(2), firm.clients.find_first("type = 'Client'")
  end

  def test_find_first_sanitized
    assert_equal Client.find(2), Firm.find_first.clients.find_first(["type = ?", "Client"])
  end

  def test_find_in_collection
    assert_equal Client.find(2).name, companies(:first_firm).clients.find(2).name
    assert_raises(ActiveRecord::RecordNotFound) { companies(:first_firm).clients.find(6) }
  end

  def test_adding
    force_signal37_to_load_all_clients_of_firm
    natural = Client.new("name" => "Natural Company")
    companies(:first_firm).clients_of_firm << natural
    assert_equal 2, companies(:first_firm).clients_of_firm.size # checking via the collection
    assert_equal 2, companies(:first_firm).clients_of_firm(true).size # checking using the db
    assert_equal natural, companies(:first_firm).clients_of_firm.last
  end
  
  def test_adding_a_mismatch_class
    assert_raises(ActiveRecord::AssociationTypeMismatch) { companies(:first_firm).clients_of_firm << nil }
    assert_raises(ActiveRecord::AssociationTypeMismatch) { companies(:first_firm).clients_of_firm << 1 }
    assert_raises(ActiveRecord::AssociationTypeMismatch) { companies(:first_firm).clients_of_firm << Topic.find(1) }
  end
  
  def test_adding_a_collection
    force_signal37_to_load_all_clients_of_firm
    companies(:first_firm).clients_of_firm.concat([Client.new("name" => "Natural Company"), Client.new("name" => "Apple")])
    assert_equal 3, companies(:first_firm).clients_of_firm.size
    assert_equal 3, companies(:first_firm).clients_of_firm(true).size
  end

  def test_adding_before_save
    no_of_firms = Firm.count
    no_of_clients = Client.count
    new_firm = Firm.new("name" => "A New Firm, Inc")
    new_firm.clients_of_firm.push Client.new("name" => "Natural Company")
    new_firm.clients_of_firm << (c = Client.new("name" => "Apple"))
    assert new_firm.new_record?
    assert c.new_record?
    assert_equal 2, new_firm.clients_of_firm.size
    assert_equal no_of_firms, Firm.count      # Firm was not saved to database.
    assert_equal no_of_clients, Client.count  # Clients were not saved to database.
    assert new_firm.save
    assert !new_firm.new_record?
    assert !c.new_record?
    assert_equal new_firm, c.firm
    assert_equal no_of_firms+1, Firm.count      # Firm was saved to database.
    assert_equal no_of_clients+2, Client.count  # Clients were saved to database.
    assert_equal 2, new_firm.clients_of_firm.size
    assert_equal 2, new_firm.clients_of_firm(true).size
  end

  def test_invalid_adding
    firm = Firm.find(1)
    assert !(firm.clients_of_firm << c = Client.new)
    assert c.new_record?
    assert !firm.save
    assert c.new_record?
  end

  def test_invalid_adding_before_save
    no_of_firms = Firm.count
    no_of_clients = Client.count
    new_firm = Firm.new("name" => "A New Firm, Inc")
    new_firm.clients_of_firm.concat([c = Client.new, Client.new("name" => "Apple")])
    assert c.new_record?
    assert !c.valid?
    assert new_firm.valid?
    assert !new_firm.save
    assert c.new_record?
    assert new_firm.new_record?
  end

  def test_build
    new_client = companies(:first_firm).clients_of_firm.build("name" => "Another Client")
    assert_equal "Another Client", new_client.name
    assert new_client.new_record?
    assert_equal new_client, companies(:first_firm).clients_of_firm.last
    assert companies(:first_firm).save
    assert !new_client.new_record?
    assert_equal 2, companies(:first_firm).clients_of_firm(true).size
  end

  def test_build_many
    new_clients = companies(:first_firm).clients_of_firm.build([{"name" => "Another Client"}, {"name" => "Another Client II"}])
    assert_equal 2, new_clients.size

    assert companies(:first_firm).save
    assert_equal 3, companies(:first_firm).clients_of_firm(true).size
  end

  def test_invalid_build
    new_client = companies(:first_firm).clients_of_firm.build
    assert new_client.new_record?
    assert !new_client.valid?
    assert_equal new_client, companies(:first_firm).clients_of_firm.last
    assert !companies(:first_firm).save
    assert new_client.new_record?
    assert_equal 1, companies(:first_firm).clients_of_firm(true).size
  end
  
  def test_create
    force_signal37_to_load_all_clients_of_firm
    new_client = companies(:first_firm).clients_of_firm.create("name" => "Another Client")
    assert !new_client.new_record?
    assert_equal new_client, companies(:first_firm).clients_of_firm.last
    assert_equal new_client, companies(:first_firm).clients_of_firm(true).last
  end
  
  def test_create_many
    companies(:first_firm).clients_of_firm.create([{"name" => "Another Client"}, {"name" => "Another Client II"}])
    assert_equal 3, companies(:first_firm).clients_of_firm(true).size
  end

  def test_deleting
    force_signal37_to_load_all_clients_of_firm
    companies(:first_firm).clients_of_firm.delete(companies(:first_firm).clients_of_firm.first)
    assert_equal 0, companies(:first_firm).clients_of_firm.size
    assert_equal 0, companies(:first_firm).clients_of_firm(true).size
  end

  def test_deleting_before_save
    new_firm = Firm.new("name" => "A New Firm, Inc.")
    new_client = new_firm.clients_of_firm.build("name" => "Another Client")
    assert_equal 1, new_firm.clients_of_firm.size
    new_firm.clients_of_firm.delete(new_client)
    assert_equal 0, new_firm.clients_of_firm.size
  end

  def test_deleting_a_collection
    force_signal37_to_load_all_clients_of_firm
    companies(:first_firm).clients_of_firm.create("name" => "Another Client")
    assert_equal 2, companies(:first_firm).clients_of_firm.size
    #companies(:first_firm).clients_of_firm.clear
    companies(:first_firm).clients_of_firm.delete([companies(:first_firm).clients_of_firm[0], companies(:first_firm).clients_of_firm[1]])
    assert_equal 0, companies(:first_firm).clients_of_firm.size
    assert_equal 0, companies(:first_firm).clients_of_firm(true).size
  end

  def test_deleting_a_association_collection
    force_signal37_to_load_all_clients_of_firm
    companies(:first_firm).clients_of_firm.create("name" => "Another Client")
    assert_equal 2, companies(:first_firm).clients_of_firm.size
    companies(:first_firm).clients_of_firm.clear
    assert_equal 0, companies(:first_firm).clients_of_firm.size
    assert_equal 0, companies(:first_firm).clients_of_firm(true).size
  end

  def test_deleting_a_item_which_is_not_in_the_collection
    force_signal37_to_load_all_clients_of_firm
    summit = Client.find_first("name = 'Summit'")
    companies(:first_firm).clients_of_firm.delete(summit)
    assert_equal 1, companies(:first_firm).clients_of_firm.size
    assert_equal 1, companies(:first_firm).clients_of_firm(true).size
    assert_equal 2, summit.client_of
  end

  def test_deleting_type_mismatch
    david = Developer.find(1)
    david.projects.reload
    assert_raises(ActiveRecord::AssociationTypeMismatch) { david.projects.delete(1) }
  end

  def test_deleting_self_type_mismatch
    david = Developer.find(1)
    david.projects.reload
    assert_raises(ActiveRecord::AssociationTypeMismatch) { david.projects.delete(Project.find(1).developers) }
  end

  def test_destroy_all
    force_signal37_to_load_all_clients_of_firm
    assert !companies(:first_firm).clients_of_firm.empty?, "37signals has clients after load"
    companies(:first_firm).clients_of_firm.destroy_all
    assert companies(:first_firm).clients_of_firm.empty?, "37signals has no clients after destroy all"
    assert companies(:first_firm).clients_of_firm(true).empty?, "37signals has no clients after destroy all and refresh"
  end

  def test_dependence
    assert_equal 2, Client.find_all.size
    Firm.find_first.destroy
    assert Client.find_all.empty?
  end

  def test_destroy_dependent_when_deleted_from_association
    firm = Firm.find_first
    assert_equal 2, firm.clients.size

    client = firm.clients.first
    firm.clients.delete(client)

    assert_raise(ActiveRecord::RecordNotFound) { Client.find(client.id) }
    assert_raise(ActiveRecord::RecordNotFound) { firm.clients.find(client.id) }
    assert_equal 1, firm.clients.size
  end

  def test_three_levels_of_dependence
    topic = Topic.create "title" => "neat and simple"
    reply = topic.replies.create "title" => "neat and simple", "content" => "still digging it"
    silly_reply = reply.silly_replies.create "title" => "neat and simple", "content" => "ain't complaining"
    
    assert_nothing_raised { topic.destroy }
  end

  def test_dependence_with_transaction_support_on_failure
    assert_equal 2, Client.find_all.length
    firm = Firm.find_first
    clients = firm.clients
    clients.last.instance_eval { def before_destroy() raise "Trigger rollback" end }

    firm.destroy rescue "do nothing"

    assert_equal 2, Client.find_all.length
  end

  def test_dependence_on_account
    assert_equal 2, Account.find_all.length
    companies(:first_firm).destroy
    assert_equal 1, Account.find_all.length
  end

  def test_included_in_collection
    assert companies(:first_firm).clients.include?(Client.find(2))
  end

  def test_adding_array_and_collection
    assert_nothing_raised { Firm.find_first.clients + Firm.find_all.last.clients }
  end
end

class BelongsToAssociationsTest < Test::Unit::TestCase
  fixtures :accounts, :companies, :developers, :projects, :topics,
           :developers_projects
  
  def test_belongs_to
    Client.find(3).firm.name
    assert_equal companies(:first_firm).name, Client.find(3).firm.name
    assert !Client.find(3).firm.nil?, "Microsoft should have a firm"   
  end

  def test_type_mismatch
    assert_raise(ActiveRecord::AssociationTypeMismatch) { Account.find(1).firm = 1 }
    assert_raise(ActiveRecord::AssociationTypeMismatch) { Account.find(1).firm = Project.find(1) }
  end

  def test_natural_assignment
    apple = Firm.create("name" => "Apple")
    citibank = Account.create("credit_limit" => 10)
    citibank.firm = apple
    assert_equal apple.id, citibank.firm_id
  end
  
  def test_creating_the_belonging_object
    citibank = Account.create("credit_limit" => 10)
    apple    = citibank.create_firm("name" => "Apple")
    assert_equal apple, citibank.firm
  end

  def test_building_the_belonging_object
    citibank = Account.create("credit_limit" => 10)
    apple    = citibank.build_firm("name" => "Apple")
    citibank.save
    assert_equal apple.id, citibank.firm_id
  end
  
  def test_natural_assignment_to_nil
    client = Client.find(3)
    client.firm = nil
    client.save
    assert_nil client.firm(true)
    assert_nil client.client_of
  end
  
  def test_with_different_class_name
    assert_equal Company.find(1).name, Company.find(3).firm_with_other_name.name
    assert_not_nil Company.find(3).firm_with_other_name, "Microsoft should have a firm"
  end

  def test_with_condition
    assert_equal Company.find(1).name, Company.find(3).firm_with_condition.name
    assert_not_nil Company.find(3).firm_with_condition, "Microsoft should have a firm"
  end
  
  def test_belongs_to_counter
    debate = Topic.create("title" => "debate")
    assert_equal 0, debate.send(:read_attribute, "replies_count"), "No replies yet"

    trash = debate.replies.create("title" => "blah!", "content" => "world around!")
    assert_equal 1, Topic.find(debate.id).send(:read_attribute, "replies_count"), "First reply created"

    trash.destroy
    assert_equal 0, Topic.find(debate.id).send(:read_attribute, "replies_count"), "First reply deleted"
  end

  def test_assignment_before_parent_saved
    client = Client.find_first
    apple = Firm.new("name" => "Apple")
    client.firm = apple
    assert_equal apple, client.firm
    assert apple.new_record?
    assert client.save
    assert apple.save
    assert !apple.new_record?
    assert_equal apple, client.firm
    assert_equal apple, client.firm(true)
  end

  def test_assignment_before_child_saved
    final_cut = Client.new("name" => "Final Cut")
    firm = Firm.find(1)
    final_cut.firm = firm
    assert final_cut.new_record?
    assert final_cut.save
    assert !final_cut.new_record?
    assert !firm.new_record?
    assert_equal firm, final_cut.firm
    assert_equal firm, final_cut.firm(true)
  end

  def test_assignment_before_either_saved
    final_cut = Client.new("name" => "Final Cut")
    apple = Firm.new("name" => "Apple")
    final_cut.firm = apple
    assert final_cut.new_record?
    assert apple.new_record?
    assert final_cut.save
    assert !final_cut.new_record?
    assert !apple.new_record?
    assert_equal apple, final_cut.firm
    assert_equal apple, final_cut.firm(true)
  end

  def test_new_record_with_foreign_key_but_no_object
    c = Client.new("firm_id" => 1)
    assert_equal Firm.find_first, c.firm_with_basic_id
  end

  def test_forgetting_the_load_when_foreign_key_enters_late
    c = Client.new
    assert_nil c.firm_with_basic_id

    c.firm_id = 1
    assert_equal Firm.find_first, c.firm_with_basic_id
  end

  def test_field_name_same_as_foreign_key
    computer = Computer.find 1
    assert_not_nil computer.developer, ":foreign key == attribute didn't lock up" # '
  end

  def xtest_counter_cache
    apple = Firm.create("name" => "Apple")
    final_cut = apple.clients.create("name" => "Final Cut")

    apple.clients.to_s
    assert_equal 1, apple.clients.size, "Created one client"
    
    apple.companies_count = 2
    apple.save

    apple = Firm.find_first("name = 'Apple'")
    assert_equal 2, apple.clients.size, "Should use the new cached number"

    apple.clients.to_s 
    assert_equal 1, apple.clients.size, "Should not use the cached number, but go to the database"
  end
end


class HasAndBelongsToManyAssociationsTest < Test::Unit::TestCase
  fixtures :accounts, :companies, :developers, :projects, :developers_projects
  
  def test_has_and_belongs_to_many
    david = Developer.find(1)

    assert !david.projects.empty?
    assert_equal 2, david.projects.size

    active_record = Project.find(1)
    assert !active_record.developers.empty?
    assert_equal 2, active_record.developers.size
    assert_equal david.name, active_record.developers.first.name
  end
  
  def test_adding_single
    jamis = Developer.find(2)
    jamis.projects.reload # causing the collection to load 
    action_controller = Project.find(2)
    assert_equal 1, jamis.projects.size
    assert_equal 1, action_controller.developers.size    
    
    jamis.projects << action_controller

    assert_equal 2, jamis.projects.size
    assert_equal 2, jamis.projects(true).size
    assert_equal 2, action_controller.developers(true).size
  end

  def test_adding_type_mismatch
    jamis = Developer.find(2)
    assert_raise(ActiveRecord::AssociationTypeMismatch) { jamis.projects << nil }
    assert_raise(ActiveRecord::AssociationTypeMismatch) { jamis.projects << 1 }
  end

  def test_adding_from_the_project
    jamis = Developer.find(2)
    action_controller = Project.find(2)
    action_controller.developers.reload
    assert_equal 1, jamis.projects.size
    assert_equal 1, action_controller.developers.size

    action_controller.developers << jamis 
    
    assert_equal 2, jamis.projects(true).size
    assert_equal 2, action_controller.developers.size
    assert_equal 2, action_controller.developers(true).size
  end

  def test_adding_multiple
    aredridel = Developer.new("name" => "Aridridel")
    aredridel.save
    aredridel.projects.reload
    aredridel.projects.push(Project.find(1), Project.find(2))
    assert_equal 2, aredridel.projects.size
    assert_equal 2, aredridel.projects(true).size
  end

  def test_adding_a_collection
    aredridel = Developer.new("name" => "Aridridel")
    aredridel.save
    aredridel.projects.reload
    aredridel.projects.concat([Project.find(1), Project.find(2)])
    assert_equal 2, aredridel.projects.size
    assert_equal 2, aredridel.projects(true).size
  end

  def test_habtm_adding_before_save
    no_of_devels = Developer.count
    no_of_projects = Project.count
    aredridel = Developer.new("name" => "Aridridel")
    aredridel.projects.concat([Project.find(1), p = Project.new("name" => "Projekt")])
    assert aredridel.new_record?
    assert p.new_record?
    assert aredridel.save
    assert !aredridel.new_record?
    assert_equal no_of_devels+1, Developer.count
    assert_equal no_of_projects+1, Project.count
    assert_equal 2, aredridel.projects.size
    assert_equal 2, aredridel.projects(true).size
  end

  def test_habtm_adding_before_save_with_join_attributes
    no_of_devels = Developer.count
    no_of_projects = Project.count
    now = Date.today
    ken = Developer.new("name" => "Ken")
    ken.projects.push_with_attributes( Project.find(1), :joined_on => now )
    p = Project.new("name" => "Foomatic")
    ken.projects.push_with_attributes( p, :joined_on => now )
    assert ken.new_record?
    assert p.new_record?
    assert ken.save
    assert !ken.new_record?
    assert_equal no_of_devels+1, Developer.count
    assert_equal no_of_projects+1, Project.count
    assert_equal 2, ken.projects.size
    assert_equal 2, ken.projects(true).size

    kenReloaded = Developer.find_by_name 'Ken'
    kenReloaded.projects.each { |prj| assert_equal(now.to_s, prj.joined_on.to_s) }
  end

  def test_build
    devel = Developer.find(1)
    proj = devel.projects.build("name" => "Projekt")
    assert_equal devel.projects.last, proj
    assert proj.new_record?
    devel.save
    assert !proj.new_record?
    assert_equal devel.projects.last, proj
  end
  
  def test_create
    devel = Developer.find(1)
    proj = devel.projects.create("name" => "Projekt")
    assert_equal devel.projects.last, proj
    assert !proj.new_record?
  end
  
  def test_uniq_after_the_fact
    developers(:jamis).projects << projects(:active_record)
    developers(:jamis).projects << projects(:active_record)
    assert_equal 3, developers(:jamis).projects.size
    assert_equal 1, developers(:jamis).projects.uniq.size
  end

  def test_uniq_before_the_fact
    projects(:active_record).developers << developers(:jamis)
    projects(:active_record).developers << developers(:david)
    assert_equal 2, projects(:active_record).developers.size
  end
  
  def test_deleting
    david = Developer.find(1)
    active_record = Project.find(1)
    david.projects.reload
    assert_equal 2, david.projects.size
    assert_equal 2, active_record.developers.size

    david.projects.delete(active_record)
    
    assert_equal 1, david.projects.size
    assert_equal 1, david.projects(true).size
    assert_equal 1, active_record.developers(true).size
  end

  def test_deleting_array
    david = Developer.find(1)
    david.projects.reload
    david.projects.delete(Project.find_all)
    assert_equal 0, david.projects.size
    assert_equal 0, david.projects(true).size
  end

  def test_deleting_with_sql
    david = Developer.find(1)
    active_record = Project.find(1)
    active_record.developers.reload
    assert_equal 2, active_record.developers_by_sql.size
    
    active_record.developers_by_sql.delete(david)
    assert_equal 1, active_record.developers_by_sql(true).size
  end

  def test_deleting_array_with_sql
    active_record = Project.find(1)
    active_record.developers.reload
    assert_equal 2, active_record.developers_by_sql.size
    
    active_record.developers_by_sql.delete(Developer.find_all)
    assert_equal 0, active_record.developers_by_sql(true).size
  end

  def test_deleting_all
    david = Developer.find(1)
    david.projects.reload
    david.projects.clear
    assert_equal 0, david.projects.size
    assert_equal 0, david.projects(true).size
  end

  def test_removing_associations_on_destroy
    Developer.find(1).destroy
    assert Developer.connection.select_all("SELECT * FROM developers_projects WHERE developer_id = 1").empty?
  end
  
  def test_additional_columns_from_join_table
    assert_equal Date.new(2004, 10, 10).to_s, Developer.find(1).projects.first.joined_on.to_s
  end
  
  def test_destroy_all
    david = Developer.find(1)
    david.projects.reload
    assert !david.projects.empty?
    david.projects.destroy_all
    assert david.projects.empty?
    assert david.projects(true).empty?
  end

  def test_rich_association
    jamis = developers(:jamis)
    jamis.projects.push_with_attributes(projects(:action_controller), :joined_on => Date.today)
    assert_equal Date.today.to_s, jamis.projects.select { |p| p.name == projects(:action_controller).name }.first.joined_on.to_s
    assert_equal Date.today.to_s, developers(:jamis).projects.select { |p| p.name == projects(:action_controller).name }.first.joined_on.to_s
  end

  def test_associations_with_conditions
    assert_equal 2, projects(:active_record).developers.size
    assert_equal 1, projects(:active_record).developers_named_david.size
    
    projects(:active_record).developers_named_david.clear
    assert_equal 1, projects(:active_record).developers.size
  end
  
  def test_find_in_association
    # Using sql
    assert_equal developers(:david), projects(:active_record).developers.find(developers(:david).id), "SQL find"
    
    # Using ruby
    active_record = projects(:active_record)
    active_record.developers.reload
    assert_equal developers(:david), active_record.developers.find(developers(:david).id), "Ruby find"
  end

  def xtest_find_in_association_with_options
    developers = projects(:active_record).developers.find(:all)
    assert_equal 2, developers.size
    
    assert_equal developers(:david), projects(:active_record).developers.find(:first, :conditions => "salary < 10000")
    assert_equal developers(:jamis), projects(:active_record).developers.find(:first, :order => "salary DESC")
  end
end
