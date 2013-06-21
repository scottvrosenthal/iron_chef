module IronChef
  module AsyncEnumerable
    def each(&block)
      pool = IronChef::ThreadPool.new(IronChef::Util.thread_pool_size)
      super do |item|
        pool.schedule(item, &block)
      end
      pool.shutdown
    end

    def map(&block)
      pool = IronChef::ThreadPool.new(IronChef::Util.thread_pool_size)
      super do |item|
        pool.schedule(item, &block)
      end
      pool.shutdown
    end
  end
end
