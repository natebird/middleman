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

        def initialize(app, options_hash={}, &block)
          super

          @store = CollectionStore.new(self)
          @collectors_by_name = {}
          @collectors = Set.new
          @realizedCollectors = {}
        end

        Contract None => Any
        def before_configuration
          app.add_to_config_context :collection, &method(:create_collection)
          app.add_to_config_context :collector, &method(:create_collector)
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

        attr_accessor :realizedCollectors
        def create_collector(name, opts={})
          parent = opts.fetch(:from, nil)

          step = LazyCollectorStep.new

          @collectors_by_name[name] = {}
          @collectors_by_name[name][:step] = step
          @collectors_by_name[name][:children] ||= Set.new

          if parent
            @collectors_by_name[parent] ||= {}
            @collectors_by_name[parent][:children] ||= Set.new
            @collectors_by_name[parent][:children] << name
          else
            @collectors << name
          end

          step
        end

        def realize_collector(key, data)
          c = @collectors_by_name[key]
          result = c[:step].dup.realize(data)

          c[:children].each do |c2|
            realize_collector(c2, result)
          end

          @realizedCollectors[key] = result
        end

        Contract ResourceList => ResourceList
        def manipulate_resource_list(resources)
          @realizedCollectors = {}

          @collectors.each do |k|
            realize_collector(k, resources)
          end

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

          def collector(name)
            extensions[:collections].realizedCollectors[name]
          end

          def pagination
            current_resource.data.pagination
          end
        end
      end

      class LazyCollectorStep < Object
        def initialize
          @compuation = nil
        end

        def realize(data)
          return data unless @compuation

          $stderr.puts "Realizing: #{data}"

          $stderr.puts "Compuation: #{@compuation}"
          name, args, block = @compuation

          result = data.send(name, *args, &block)

          $stderr.puts "Result: #{result}"

          @next_step.realize(result)
        end

        def method_missing(name, *args, &block)
          @compuation = [name, args, block]
          @next_step = LazyCollectorStep.new
        end
      end
    end
  end
end
