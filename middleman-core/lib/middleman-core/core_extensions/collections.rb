require 'middleman-core/sitemap/extensions/proxies'
require 'middleman-core/util'
require 'middleman-core/core_extensions/collections/collection_store'
require 'middleman-core/core_extensions/collections/collection'
require 'middleman-core/core_extensions/collections/grouped_collection'

module Middleman
  module CoreExtensions
    module Collections
      class CollectionsExtension < Extension
        # This should run after most other sitemap manipulators so that it
        # gets a chance to modify any new resources that get added.
        self.resource_list_manipulator_priority = 110

        attr_accessor :root_collector

        def initialize(app, options_hash={}, &block)
          super

          @store = CollectionStore.new(self)
          @collectors_by_name = {}

          @root_collector = LazyCollectorRoot.new
        end

        Contract None => Any
        def before_configuration
          app.add_to_config_context :collection, &method(:create_collection)
          app.add_to_config_context :resources, &method(:root_collector)
          app.add_to_config_context :collector, &method(:register_collector)
          app.add_to_config_context :uri_match, &@store.method(:uri_match)
        end

        EitherCollection = Or[Collection, GroupedCollection]
        # rubocop:disable ParenthesesAsGroupedExpression
        Contract ({ where: Or[String, Proc], group_by: Maybe[Proc], as: Maybe[Symbol] }) => EitherCollection
        def create_collection(options={})
          @store.add(
            options.fetch(:as, :"anonymous_collection_#{@store.collections.length + 1}"),
            options.fetch(:where),
            options.fetch(:group_by, nil)
          )
        end

        def register_collector(label, endpoint)
          @collectors_by_name[label] = endpoint
        end

        def collector_value(label)
          @collectors_by_name[label].value
        end

        Contract ResourceList => ResourceList
        def manipulate_resource_list(resources)
          @root_collector.realize!(resources)

          @store.manipulate_resource_list(resources)
        end

        Contract None => CollectionStore
        def collected
          @store
        end

        helpers do
          def collected
            extensions[:collections].collected
          end

          def collector(label)
            extensions[:collections].collector_value(label)
          end

          def pagination
            current_resource.data.pagination
          end
        end
      end

      class LazyCollectorRoot < Object
        DELEGATE = [:hash, :eql?]

        def initialize
          @data = nil
        end

        def realize!(data)
          @data = data
        end

        def value
          @data
        end

        def method_missing(name, *args, &block)
          LazyCollectorStep.new([name, args, block], self)
        end
      end

      LEAVES = Set.new

      class LazyCollectorStep < BasicObject
        DELEGATE = [:hash, :eql?]

        def initialize(computation, parent=nil)
          @name, @args, @block = computation
          @parent = parent
          @result = nil

          LEAVES << self
        end

        def value
          @result ||= begin
            data = @parent.value
            data.send(@name, *@args, &@block)
          end
        end

        def method_missing(name, *args, &block)
          if DELEGATE.include? name
            return ::Kernel.send(name, *args, &block)
          end

          # Remove from leaves
          LEAVES.delete self

          LazyCollectorStep.new([name, args, block], self)
        end
      end
    end
  end
end
