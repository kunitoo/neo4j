module Neo4j
  module ActiveNode


    # Provides a mapping between neo4j labels and Ruby classes
    module Labels
      extend ActiveSupport::Concern

      WRAPPED_CLASSES = []
      class InvalidQueryError < StandardError; end
      class RecordNotFound < StandardError; end

      # @return the labels
      # @see Neo4j-core
      def labels
        @_persisted_node.labels
      end

      # adds one or more labels
      # @see Neo4j-core
      def add_label(*label)
        @_persisted_node.add_label(*label)
      end

      # Removes one or more labels
      # Be careful, don't remove the label representing the Ruby class.
      # @see Neo4j-core
      def remove_label(*label)
        @_persisted_node.remove_label(*label)
      end

      def self.included(klass)
        add_wrapped_class(klass)
      end

      def self.add_wrapped_class(klass)
        _wrapped_classes << klass
        @_wrapped_labels = nil
      end

      def self._wrapped_classes
        Neo4j::ActiveNode::Labels::WRAPPED_CLASSES
      end

      protected

      # Only for testing purpose
      # @private
      def self._wrapped_labels=(wl)
        @_wrapped_labels=(wl)
      end

      def self._wrapped_labels
        @_wrapped_labels ||=  _wrapped_classes.inject({}) do |ack, clazz|
          ack.tap do |a|
            a[clazz.mapped_label_name.to_sym] = clazz if clazz.respond_to?(:mapped_label_name)
          end
        end
      end

      module ClassMethods

        # Find all nodes/objects of this class
        def all
          self.query_as(:n).pluck(:n)
        end

        def first
          self.query_as(:n).limit(1).order('n.neo_id').pluck(:n).first
        end

        def last
          count = self.count
          final_count = count == 0 ? 0 : count - 1
          self.query_as(:n).order('n.neo_id').skip(final_count).limit(1).pluck(:n).first
        end

        # @return [Fixnum] number of nodes of this class
        def count
          self.query_as(:n).return("count(n) AS count").first.count
        end

        # Returns the object with the specified neo4j id.
        # @param [String,Fixnum] neo_id of node to find
        def find(id)
          raise "Unknown argument #{id.class} in find method" if not [String, Fixnum].include?(id.class)
          
          Neo4j::Node.load(id.to_i)
        end

        # Finds the first record matching the specified conditions. There is no implied ordering so if order matters, you should specify it yourself.
        # @param [Hash] hash of arguments to find 
        def find_by(*args)
          self.query_as(:n).where(n: eval(args.join)).limit(1).pluck(:n).first
        end

        # Like find_by, except that if no record is found, raises a RecordNotFound error. 
        def find_by!(*args)
          a = eval(args.join)
          find_by(args) or raise RecordNotFound, "#{self.query_as(:n).where(n: a).limit(1).to_cypher} returned no results"
        end

        # Destroy all nodes an connected relationships
        def destroy_all
          self.neo4j_session._query("MATCH (n:`#{mapped_label_name}`)-[r]-() DELETE n,r")
          self.neo4j_session._query("MATCH (n:`#{mapped_label_name}`) DELETE n")
        end

        # Creates a Neo4j index on given property
        # @param [Symbol] property the property we want a Neo4j index on
        def index(property)
          if self.neo4j_session
            _index(property)
          else
            Neo4j::Session.add_listener do |event, _|
              _index(property) if event == :session_available
            end
          end
        end

        def index?(index_def)
          mapped_label.indexes[:property_keys].include?(index_def)
        end

        # @return [Array{Symbol}] all the labels that this class has
        def mapped_label_names
          self.ancestors.find_all { |a| a.respond_to?(:mapped_label_name) }.map { |a| a.mapped_label_name.to_sym }
        end

        # @return [Symbol] the label that this class has which corresponds to a Ruby class
        def mapped_label_name
          @_label_name || self.to_s.to_sym
        end

        def indexed_labels

        end

        protected

        def _index(property)
          mapped_labels.each do |label|
            # make sure the property is not indexed twice
            existing = label.indexes[:property_keys]
            label.create_index(property) unless existing.flatten.include?(property)
          end
        end

        def mapped_labels
          mapped_label_names.map{|label_name| Neo4j::Label.create(label_name)}
        end

        def mapped_label
          Neo4j::Label.create(mapped_label_name)
        end

        def set_mapped_label_name(name)
          @_label_name = name.to_sym
        end

      end

    end

  end
end