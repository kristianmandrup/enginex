require "thor/group"
require "active_support"
require "active_support/version"
require "active_support/core_ext/string"

require "rails/generators"
require "rails/generators/rails/app/app_generator"

require "sugar-high/file"

class Enginex < Thor::Group
  include Thor::Actions
  check_unknown_options!

  def self.source_root
    @_source_root ||= File.expand_path('../templates', __FILE__)
  end

  def self.say_step(message)
    @step = (@step || 0) + 1
    class_eval <<-METHOD, __FILE__, __LINE__ + 1
      def step_#{@step}
        #{"puts" if @step > 1}
        say_status "STEP #{@step}", #{message.inspect}
      end
    METHOD
  end

  argument :path, :type => :string,
                  :desc => "Path to the engine to be created"

  class_option :test_framework, :default => "test_unit", :aliases => "-t",
                                :desc => "Test framework to use. test_unit or rspec."

  class_option :orms, :type => :array, :default => ['active_record'], :aliases => "-o",
                                :desc => "Datastore frameworks to use. mongoid or active_record."

  class_option :tu,  :type => :boolean, :default => true,
                                :desc => "Skip testunit generation for dummy apps."

  class_option :js,  :type => :boolean, :default => true,
                                :desc => "Skip javascript generation for dummy apps."

  class_option :postfixes,  :type => :array, :default => [],
                                :desc => "Special app configurations (or types) fx authlogic/devise etc"

  
  desc "Creates a Rails 3 engine with Rakefile, Gemfile and running tests."

  say_step "Creating gem skeleton"

  def create_root
    self.destination_root = File.expand_path(path, destination_root)
    set_accessors!

    directory "root", "."
    FileUtils.cd(destination_root)
  end

  def create_tests_or_specs
    directory test_path
  end

  def change_gitignore
    template "gitignore", ".gitignore"
  end

  say_step "Vendoring Rails applications at test/dummy-apps"

  def invoke_rails_app_generators
    postfixes.each do |postfix|
      orms.each do |orm| 
        dummy_app_path = app_path orm, postfix

        say_step "Creating dummy Rails app with #{orm}"
        invoke Rails::Generators::AppGenerator, app_args(orm)      

        say_step "Configuring Rails app"
        change_config_files dummy_app_path

        say_step "Removing unneeded files"
        remove_uneeded_rails_files dummy_app_path
            
        if respond_to? orm_config_method(orm)
          say_step "Configuring app for #{orm}"
          send orm_config_method(orm), dummy_app_path
        end

        say_step "Configuring testing framework for #{orm}"      
        set_orm_helpers orm
      end
    end
  end

  protected

    def set_orm_helpers orm, postfix
      dummy_app_path = app_path orm, postfix
      inside dummy_app_path do
        inside test_path do
          if rspec?
            File.replace_content_from 'integration/navigation_spec.rb', :where => '#orm#', :with => orm
            File.replace_content_from "integration/#{underscored}_spec.rb", :where => '#orm#', :with => orm        
          else
            say "Not implemented for test unit"
          end
        end
      end
    end

    def orm_config_method orm
      "config_#{orm}"
    end

    def config_mongoid
      inside dummy_app_path do
        gemfile = File.new('Gemfile')
        gemfile.insert :after => 'gem "sqlite3"' do 
         %q{gem "mongoid"
gem "bson_ext"
}
        end
        gemfile.remove_content 'gem "sqlite3"'
        `bundle install`
        `rails g mongoid:config`
      end
    end

    def remove_uneeded_rails_files dummy_app_path
      inside dummy_app_path do
        remove_file ".gitignore"
        # remove_file "db/seeds.rb"
        remove_file "doc"
        # remove_file "Gemfile"
        remove_file "lib/tasks"
        remove_file "public/images/rails.png"
        remove_file "public/index.html"
        remove_file "public/robots.txt"
        remove_file "README"
        remove_file "test"
        remove_file "vendor"
      end
    end

    def change_config_files dummy_app_path
      store_application_definition! dummy_app_path
      template "rails/boot.rb", "#{dummy_app_path}/config/boot.rb", :force => true
      template "rails/application.rb", "#{dummy_app_path}/config/application.rb", :force => true
    end
  
    def app_path orm
      File.expand_path(dummy_path orm, destination_root)
    end

    def app_args orm
      args = [app_path(orm), "-T"] # skip test unit
      args << "-T" if skip_testunit?
      args << "-J" if skip_javascript?      
      # skip active record is orm is set to another datastore      
      args << "-O" if !active_record? orm
      args
    end

    def active_record? orm
      !orm || is_ar?(orm)
    end

    def is_ar? orm
      ['active_record', 'ar'].include?(orm)
    end

    def skip_testunit?
      options[:tu]
    end

    def skip_javascript?
      options[:js]
    end

    def rspec?
      options[:test_framework] == "rspec"
    end

    def test_unit?
      options[:test_framework] == "test_unit"
    end

    def test_path
      rspec? ? "spec" : "test"
    end

    def dummy_path orm = 'active_record'
      "#{test_path}/dummy-apps/dummy-#{orm}"
    end

    def self.banner
      self_task.formatted_usage(self, false)
    end

    def application_definition dummy_app_path
      @application_definition ||= begin
        contents = File.read(File.expand_path("#{dummy_app_path}/config/application.rb", destination_root))
        contents[(contents.index("module Dummy"))..-1]
      end
    end
    alias :store_application_definition! :application_definition

    # Cache accessors since we are changing the directory
    def set_accessors!
      self.name
      self.class.source_root
    end

    def name
      @name ||= File.basename(destination_root)
    end

    def camelized
      @camelized ||= name.camelize
    end

    def underscored
      @underscored ||= name.underscore
    end
end
