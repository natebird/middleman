Feature: Collections
  Scenario: Lazy query
    Given a fixture app "collections-app"
    And a file named "config.rb" with:
      """
      articles1 = resources.select do |r|
        uri_match r.url, 'blog1/{year}-{month}-{day}-{title}.html'
      end

      everything = resources.select do |r|
        true
      end

      def get_tags(resource)
        if resource.data.tags.is_a? String
          resource.data.tags.split(',').map(&:strip)
        else
          resource.data.tags
        end
      end

      def group_lookup(resource, sum)
        results = Array(get_tags(resource)).map(&:to_s).map(&:to_sym)

        results.each do |k|
          sum[k] ||= []
          sum[k] << resource
        end
      end

      tags = everything
          .select { |resource| resource.data.tags }
          .each_with_object({}, &method(:group_lookup))

      first_tag = tags.keys.sort.first

      class Wrapper
        def initialize
          @stuff = []
        end

        def <<(item)
          @stuff << item
        end
      end

      wrapped = tags.reduce(Wrapper.new, :<<)

      # Expose to templates
      collector(:articles1, articles1)
      set :tags, tags
      set :first_tag, first_tag
      """
    And a file named "source/index.html.erb" with:
      """
      <% collector(:articles1).each do |article| %>
        Article1: <%= article.data.title %>
      <% end %>

      <% config[:tags].value.each do |k, items| %>
        Tag: <%= k %> (<%= items.length %>)
        <% items.each do |article| %>
          Article (<%= k %>): <%= article.data.title %>
        <% end %>
      <% end %>

      First Tag: <%= config[:first_tag].value %>
      """
    Given the Server is running at "collections-app"
    When I go to "index.html"
    Then I should see 'Article1: Blog1 Newer Article'
    And I should see 'Article1: Blog1 Another Article'
    And I should see 'Tag: foo (4)'
    And I should see 'Article (foo): Blog1 Newer Article'
    And I should see 'Article (foo): Blog1 Another Article'
    And I should see 'Article (foo): Blog2 Newer Article'
    And I should see 'Article (foo): Blog2 Another Article'
    And I should see 'Tag: bar (2)'
    And I should see 'Article (bar): Blog1 Newer Article'
    And I should see 'Article (bar): Blog2 Newer Article'
    And I should see 'Tag: 120 (1)'
    And I should see 'Article (120): Blog1 Another Article'
    And I should see 'First Tag: 120'

  Scenario: Collect resource by proc or string
    Given a fixture app "collections-app"
    And a file named "config.rb" with:
      """
      collection as: :articles1,
        where: proc { |resource|
          uri_match resource.url, 'blog1/{year}-{month}-{day}-{title}.html'
        }
      collection as: :articles2,
        where: 'blog2/{year}-{month}-{day}-{title}.html'
      """
    And a file named "source/index.html.erb" with:
      """
      <% collected.articles1.each do |article| %>
        Article1: <%= article.data.title %>
      <% end %>

      <% collected.articles2.each do |article| %>
        Article2: <%= article.data.title %>
      <% end %>
      """
    Given the Server is running at "collections-app"
    When I go to "index.html"
    Then I should see 'Article1: Blog1 Newer Article'
    And I should see 'Article1: Blog1 Another Article'
    Then I should see 'Article2: Blog2 Newer Article'
    And I should see 'Article2: Blog2 Another Article'

  Scenario: Group collected resource by proc
    Given a fixture app "collections-app"
    And a file named "config.rb" with:
      """
      collection as: :tags,
        where: proc { |resource| resource.data.tags },
        group_by: proc { |resource|
          if resource.data.tags.is_a? String
            resource.data.tags.split(',').map(&:strip)
          else
            resource.data.tags
          end
        }
      """
    And a file named "source/index.html.erb" with:
      """
      <% collected[:tags].each do |k, items| %>
        Tag: <%= k %> (<%= items.length %>)
        <% items.each do |article| %>
          Article (<%= k %>): <%= article.data.title %>
        <% end %>
      <% end %>
      """
    Given the Server is running at "collections-app"
    When I go to "index.html"
    Then I should see 'Tag: foo (4)'
    And I should see 'Article (foo): Blog1 Newer Article'
    And I should see 'Article (foo): Blog1 Another Article'
    And I should see 'Article (foo): Blog2 Newer Article'
    And I should see 'Article (foo): Blog2 Another Article'
    And I should see 'Tag: bar (2)'
    And I should see 'Article (bar): Blog1 Newer Article'
    And I should see 'Article (bar): Blog2 Newer Article'
    And I should see 'Tag: 120 (1)'
    And I should see 'Article (120): Blog1 Another Article'

  Scenario: Collected resources update with file changes
    Given a fixture app "collections-app"
    And a file named "config.rb" with:
      """
      collection as: :articles,
        where: 'blog2/{year}-{month}-{day}-{title}.html'
      """
    And a file named "source/index.html.erb" with:
      """
      <% collected.articles.each do |article| %>
        Article: <%= article.data.title %>
      <% end %>
      """
    Given the Server is running at "collections-app"
    When I go to "index.html"
    Then I should see 'Article: Blog2 Newer Article'
    And I should see 'Article: Blog2 Another Article'

    And the file "source/blog2/2011-01-02-another-article.html.markdown" has the contents
      """
      ---
      title: "Blog3 Another Article"
      date: 2011-01-02
      tags:
        - foo
      ---

      Another Article Content

      """
    When I go to "index.html"
    Then I should see "Article: Blog2 Newer Article"
    And I should not see "Article: Blog2 Another Article"
    And I should see 'Article: Blog3 Another Article'

    And the file "source/blog2/2011-01-01-new-article.html.markdown" is removed
    When I go to "index.html"
    Then I should not see "Article: Blog2 Newer Article"
    And I should see 'Article: Blog3 Another Article'

    And the file "source/blog2/2014-01-02-yet-another-article.html.markdown" has the contents
      """
      ---
      title: "Blog2 Yet Another Article"
      date: 2011-01-02
      tags:
        - foo
      ---

      Yet Another Article Content
      """
    When I go to "index.html"
    And I should see 'Article: Blog3 Another Article'
    And I should see 'Article: Blog2 Yet Another Article'