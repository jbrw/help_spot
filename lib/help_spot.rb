require 'uri'
require 'net/http'
require 'json'

##
# help_spot
#
# A partial basic implementation of a HelpSpot API interface
#
# == Using help_spot
#
# === Basics
#
# Copy and edit the included config file. Include the gem in your app. Call the configure method. Hit the API.
#
#   require 'help_spot'
#   HelpSpot.configure(:app_root => '/my_app/')
#   HelpSpot.forums_list
#
#   => [{"xForumId"=>"1", "fClosed"=>"0", "sForumName"=>"The First Forum", "iOrder"=>"0", "sDescription"=>"A test forum"}, {"xForumId"=>"2", "fClosed"=>"0", "sForumName"=>"Secondary Forum", "iOrder"=>"0", "sDescription"=>"Forum #2"}]
#

module HelpSpot
  class << self

    # Loads the config file.
    # 
    # == Options
    # * app_root (optional)
    #     Path to the root directory of your app. Shouldn't be required when using merb or Rails.
    # * config_file (optional)
    #     Defaults to '/config/help_spot.yml'
    #
    def configure(args={})    
      # work out the default app_root
      if args[:app_root]
        app_root = args[:app_root]
      elsif defined?(Merb)
        app_root = Merb.root
      elsif defined?(Rails)
        app_root = RAILS_ROOT
      else
        app_root = '.'
      end
      
      config_file = args[:config_file] || '/config/help_spot.yml'
      yml_file    = app_root+config_file
      
      raise yml_file+" not found" unless File.exist? yml_file
      @config = YAML.load_file(yml_file)
    end

    # sends a feedback request to HelpSpot and returns the request ID number and access key
    #
    # == Options
    # In addition to note you must also have at least one of the following set: first_name, last_name, user_id, email or phone
    # * note
    #     The body of the ticket
    # * category
    # * first_name
    # * last_name
    # * user_id
    # * email
    # * phone
    # * urgent
    #     A boolean flag. Defaults to false.
    #
    def create(args)                   
      help_form = {:tNote       => args[:note],
                   :xCategory   => args[:category],
                   :sFirstName  => args[:first_name],
                   :sLastName   => args[:last_name],
                   :sUserId     => args[:user_id],
                   :sEmail      => args[:email],
                   :sPhone      => args[:phone],
                   :fUrgent     => args[:urgent]}.reject!{|k,v| v == nil}
                   
      JSON.parse(api_request('request.create', 'POST', help_form))['xRequest'] rescue []
    end

    # Returns an array of tickets belonging to a given user id.
    # 
    # == Authentication
    # This method does require authentication.
    # 
    # == Options
    # * user_id
    #     The user who's tickets you wish to view.
    #
    def get_by_user_id(args)
      JSON.parse(api_request('private.request.search', 'GET', {:sUserId => args[:user_id]}))['request'] rescue nil
    end

    # Returns ticket categories.
    # 
    # == Authentication
    # This method does require authentication.
    # 
    # == Options
    # * include_deleted
    #     true if you want to include deleted categories. 
    #
    def categories(args={})
      res = api_request('private.request.getCategories', 'GET')
      res = JSON.parse(res)['category'] rescue []

      unless args[:include_deleted] and args[:include_deleted] == true
        res.reject!{|k, v| v['fDeleted'] == '1'} rescue []
      end
      
      return res
    end
    
    # Returns an array of non-deleted categories, as key value pairs. Useful for select lists.
    # 
    # == Authentication
    # This method does require authentication.
    # 
    def category_key_value_pairs
      categories.collect{|k,v| [k,v['sCategory']]} rescue []
    end
    
    # Returns non-deleted categories, with a list of predefined categories removed
    #
    def category_key_value_pairs_without(categories=nil)
      categories ||= @config['hidden_categories'] rescue nil
      
      orig_categories = category_key_value_pairs
      if categories
        categories.each do |category|
          orig_categories.reject!{|i| i[1] == category}
        end
      end
      orig_categories
    end
    
    # Returns an array of forums
    #
    def forums_list
      JSON.parse(HelpSpot.api_request('forums.list'))['forum'] rescue []
    end
    
    # Returns an array of forums
    #
    # == Options
    # * forum_id
    #     The numeric id of the forum you want.
    def forum_get(args)
      JSON.parse(HelpSpot.api_request('forums.get', 'GET', :xForumId => args[:forum_id])) rescue []
    end
    
    # Returns an array of topics from a given forum
    #
    # == Options
    # * forum_id
    #     The numeric id of the forum you want.
    # * start
    #     record set position to start at
    # * length
    #     how many records to return
    #
    def forum_get_topics(args={})
      JSON.parse(HelpSpot.api_request('forums.getTopics', 'GET', {:xForumId => args[:forum_id]}.merge(args)))['topic'] rescue []
    end
    
    # Returns an array of posts from a given topic
    #
    # == Options
    # * topic_id
    #     The numeric id of the topic
    #
    def forum_get_topic_posts(args={})
      JSON.parse(HelpSpot.api_request('forums.getPosts', 'GET', :xTopicId => args[:topic_id]))['post'] rescue []
    end
    

    #private
      def api_request(api_method, http_method='POST', args={})
        api_params =  {:method => api_method, :output => 'json'}.merge(args)
        query_params = api_params.collect{|k,v| [k.to_s, v.to_s]} # [URI.encode(k.to_s),URI.encode(v.to_s.gsub(/\ /, '+'))]
        built_query  = query_params.collect{|i| i.join('=')}.join('&') # make a query string
    
        ru = URI::parse(@config['root_url']) # where ru = ROOT_URL
        merged_query = [built_query, (ru.query == '' ? nil : ru.query)].compact.join('&') # merge our generated query string with the ROOT_URL's query string
    
        url = URI::HTTP.new(ru.scheme, ru.userinfo, ru.host, ru.port, ru.registry, ru.path, ru.opaque, merged_query, ru.fragment)
    
        if http_method == 'POST'
          req = Net::HTTP::Post.new(url.path)
          req.set_form_data(query_params)
          req.basic_auth @config['username'], @config['password']
          res = Net::HTTP.new(url.host, url.port).start {|http| http.request(req) }
        else
          req = Net::HTTP::Get.new(url.path+'?'+url.query)
          req.basic_auth @config['username'], @config['password']
          res = Net::HTTP.start(url.host, url.port) {|http| http.request(req) }
        end

        res.body
      end
      
  end # class
end # module


if defined?(Merb::Plugins)
  Merb::BootLoader.after_app_loads do
    HelpSpot.configure
    HELPSPOT_CATEGORIES = HelpSpot.category_key_value_pairs_without().sort rescue []
  end
end
