
require "yaml"
require "bson"

# ProjectHanlon::Utility namespace
module ProjectHanlon
  module Utility

    # Returns a hash array of instance variable symbol and instance variable value for self
    # will ignore instance variables that start with '_'
    def to_hash
      hash = {}
      self.instance_variables.each do |iv|
        if !iv.to_s.start_with?("@_") && self.instance_variable_get(iv).class != Logger
          if self.instance_variable_get(iv).class == Array
            new_array = []
            self.instance_variable_get(iv).each do
            |val|
              if val.respond_to?(:to_hash)
                new_array << val.to_hash
              else
                new_array << val
              end
            end
            hash[iv.to_s] = new_array
          else
            if self.instance_variable_get(iv).respond_to?(:to_hash)
              hash[iv.to_s] = self.instance_variable_get(iv).to_hash
            else
              hash[iv.to_s] = self.instance_variable_get(iv)
            end
          end
        end
      end
      hash
    end

    # Sets instance variables
    # will not include any that start with "_" (Mongo specific)
    # @param [Hash] hash
    def from_hash(hash)
      hash.each_pair do |key, value|

        # We need to catch hashes representing child objects
        # If the hash key:value is a of a Hash/BSON:Ordered hash
        if hash[key].class == Hash || hash[key].class == BSON::OrderedHash
          # If we have a classname we know we need to return to an object
          if hash[key]["@classname"]
            self.instance_variable_set(key, ::Object::full_const_get(hash[key]["@classname"]).new(hash[key])) unless key.to_s.start_with?("_")
          else
            self.instance_variable_set(key, value) unless key.to_s.start_with?("_")
          end
        else
          self.instance_variable_set(key, value) unless key.to_s.start_with?("_")
        end
      end
    end

    def to_json
      # sorts based on the key value and removes the "@noun" key from the
      # configuration hashmap (it's really just for internal use)
      Hash[*(to_hash.reject{ |k| k == "@noun" }).sort.flatten].to_json
    end

    def new_object_from_template_name(namespace_prefix, object_template_name)
      get_child_types(namespace_prefix).each do
      |template|
        return template if template.template.to_s == object_template_name
      end
      nil
    end

    # searches for an executable (command) in the current path
    def exec_in_path(command)
      ENV['PATH'].split(':').collect {|d| Dir.entries d if Dir.exists? d}.flatten.include?(command)
    end

    alias :new_object_from_type_name :new_object_from_template_name


    def sanitize_hash(in_hash)
      in_hash.inject({}) {|h, (k, v)| h[k.sub(/^@/, '')] = v; h }
    end


    # converts a BSON::OrderedHash to a regular Ruby Hash
    # (useful for outputting a hash as YAML without Ruby-specific
    # extensions being embedded in the resulting YAML file)
    def bson_ordered_hash_to_hash(bson_ordered_hash)
      new_hash = {}
      # loop through the BSON::OrderedHash
      bson_ordered_hash.each { |key, val|
        # if the element is a BSON::OrderedHash, then iterate, else if it is
        # an Array, check each element of the array to see if any of them are
        # BSON::OrderedHash objects (and if so, convert them), otherwise
        # just move the value from one hash to the other
        if val.class == BSON::OrderedHash
          new_hash[key] = bson_ordered_hash_to_hash(val)
        elsif val.class == Array
          new_hash[key] = bson_hash_array_to_hash_array(val)
        else
          new_hash[key] = val
        end
      }
      # finally, return the coverted Hash
      new_hash
    end

    # used in conjunction with the bson_ordered_hash_to_hash
    # method (above) to test array elements for BSON::OrderedHash
    # elements and convert them to regular Ruby Hash elements
    def bson_hash_array_to_hash_array(array)
      new_array = []
      array.each { |elem|
        if elem.class == BSON::OrderedHash
          new_array << bson_ordered_hash_to_hash(elem)
        elsif elem.class == Array
          new_array << bson_hash_array_to_hash_array(elem)
        else
          new_array << elem
        end
      }
      new_array
    end

    def self.encode_symbols_in_hash(obj)
      case obj
      when Hash
        encoded = Hash.new
        obj.each_pair { |key, value| encoded[key] = encode_symbols_in_hash(value) }
        encoded
      when Array
        obj.map { |item| encode_symbols_in_hash(item) }
      when Symbol
        ":#{obj}"
      else
        obj
      end
    end

    def self.decode_symbols_in_hash(obj)
      case obj
      when Hash
        decoded = Hash.new
        obj.each_pair { |key, value| decoded[key] = decode_symbols_in_hash(value) }
        decoded
      when Array
        obj.map { |item| decode_symbols_in_hash(item) }
      when /^:/
        obj.sub(/^:/, '').to_sym
      else
        obj
      end
    end
  end
end
