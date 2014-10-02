require 'middleman-core/sitemap/extensions/proxies'
require 'middleman-core/util'
require 'middleman-core/core_extensions/paginator'
require 'active_support/core_ext/object/deep_dup'

class Array
  def per_page(per_page, &block)
    parts = if per_page.is_a? Fixnum
      each_slice(per_page).reduce([]) do |sum, items|
        sum << items
      end
    else
      per_page.call(self.dup)
    end

    num_pages = parts.length

    collection = self

    # DefaultPaginator.new(app, collection, opts, &block)
    current_start_i = 0
    parts.each_with_index do |items, i|
      num = i + 1

      meta = ::Middleman::Paginator.page_locals(
        num,
        num_pages,
        collection,
        items,
        current_start_i
      )

      yield items, num, meta, num >= num_pages

      current_start_i += items.length
    end
  end
end

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

          @collectors_by_name = {}
          @values_by_name = {}

          @root_collector = LazyCollectorRoot.new
        end

        Contract None => Any
        def before_configuration
          app.add_to_config_context :resources, &method(:root_collector)
          app.add_to_config_context :collection, &method(:register_collector)
        end

        def register_collector(label, endpoint)
          @collectors_by_name[label] = endpoint
        end

        def collector_value(label)
          @values_by_name[label]
        end

        def step_context
          StepContext
        end

        Contract ResourceList => ResourceList
        def manipulate_resource_list(resources)
          @root_collector.realize!(resources)

          ctx = StepContext.new
          leafs = LEAFS.dup

          @collectors_by_name.each do |k, v|
            @values_by_name[k] = v.value(ctx)
            leafs.delete v
          end

          # Execute code paths
          leafs.each do |v|
            v.value(ctx)
          end

          # Inject descriptors 
          # $stderr.puts ctx.descriptors.map(&:path).inspect
          resources + ctx.descriptors.map { |d| d.to_resource(app) }
        end

        helpers do
          def collection(label)
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

        def value(ctx=nil)
          @data
        end

        def method_missing(name, *args, &block)
          LazyCollectorStep.new(name, args, block, self)
        end
      end

      class StepContext
        def self.add_to_context(name, &func)
          send(:define_method, :"_internal_#{name}", &func)
        end

        attr_reader :descriptors

        def initialize
          @descriptors = []
        end

        def method_missing(name, *args, &block)
          internal = :"_internal_#{name}"
          if respond_to?(internal)
            @descriptors << send(internal, *args, &block)
          else
            super
          end
        end

        # def all_resources(app)
        #   @descriptors.map { |d| d.to_resource(app) }
        # end
      end

      LEAFS = Set.new

      class LazyCollectorStep < BasicObject
        DELEGATE = [:hash, :eql?]

        def initialize(name, args, block, parent=nil)
          @name = name
          @args = args
          @block = block

          @parent = parent
          @result = nil

          LEAFS << self
        end

        def value(ctx=nil)
          data = @parent.value(ctx)

          original_block = @block

          b = if ctx
            ::Proc.new do |*args|
              ctx.instance_exec(*args, &original_block)
            end
          else
            original_block
          end if original_block

          data.send(@name, *@args.deep_dup, &b)
        end

        def method_missing(name, *args, &block)
          if DELEGATE.include? name
            return ::Kernel.send(name, *args, &block)
          end

          LEAFS.delete self

          LazyCollectorStep.new(name, args, block, self)
        end
      end
    end
  end
end
