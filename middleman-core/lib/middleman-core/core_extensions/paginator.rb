module Middleman
  module Paginator
    def self.page_locals(page_num, num_pages, collection, items, page_start)
      per_page = items.length

      # Index into collection of the last item of this page
      page_end = (page_start + per_page) - 1

      ::Middleman::Util.recursively_enhance({
        # Include the numbers, useful for displaying "Page X of Y"
        page_number: page_num,
        num_pages: num_pages,
        per_page: per_page,

        # The range of item numbers on this page
        # (1-based, for showing "Items X to Y of Z")
        page_start: page_start + 1,
        page_end: [page_end + 1, collection.length].min,

        # Use "collection" in templates.
        collection: collection
      })
    end
  end
end
