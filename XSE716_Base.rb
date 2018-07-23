#多出来的参数忽略，不足的参数自动补nil
class Proc
  def exec(*args)
    if self.arity<-1
      args[-self.arity-2] = nil if args[-self.arity-2].nil?
      self.call(*args)
    elsif self.arity==-1
      self.call(*args)
    else
      args[self.arity] = nil if args[self.arity].nil?
      self.call(*args[0,self.arity])
    end
  end
end
#代理
module XSE716_Proxy
  def method_missing(method,*args)
    m = nil
    begin
      m = @window.method(method)
    rescue NameError => e
      raise(e,e.message,caller[1])
    end
    begin
      return m.call(*args)
    rescue Exception => e
      if $@.size==caller.size+1
        raise(e,e.message,caller[1])
      else
        raise(e,e.message,e.backtrace[0])
      end
    end
  end
end
class Action
  now = nil
  need_cencal = false
  class ActionError<Exception
  end
  class CencalInRunningError<Exception
  end
  define_method(:initialize) do |fun|
    define_singleton_method(:to_proc){fun}
    @fiber = Fiber.new do
      lambda do
        @ret = Proc.new{return}
        @values = fun.exec(*Action.pause)
      end.call
      @outer.cencal if @outer
      @cencal.exec if @cencal
      @fiber = @cencal = @outer= @ret = nil
    end
    last = now
    now = self
    @fiber.resume
    now = last
  end
  define_method(:cencal) do
    return self unless @fiber
    need_cencal = true
    begin
      self.next
    rescue ActionError=>e
      raise(CencalInRunningError,e.message,caller[1])
    end
    return self
  end
  define_method(:next) do |value=nil|
    return self unless @fiber
    save = now
    begin
      r = @fiber.resume(value)
    rescue FiberError=>e
      raise(ActionError,e.message,caller[1])
    end
    @values = r if @fiber
    now = save
    return self
  end
  def running?
    return @fiber&&true
  end
  def values(&fun)
    fun.exec(*@values)
    return self
  end
  define_singleton_method(:current){now}
  define_singleton_method(:pause) do |*args|
    return unless now
    (save = now).instance_eval{@values = args}
    value = Fiber.yield(args)
    now = save
    if need_cencal
      need_cencal = false
      now.instance_eval{@ret.call}
    end
    now.instance_eval do
      if @outer&&(not @outer.next.running?)
        @outer.values{|*args|@values = args}
        @ret.call
      end
    end
    return value
  end
  define_singleton_method(:set) do |&fun|
    now.instance_eval{@cencal = fun} if now
    return fun
  end
  define_singleton_method(:set_outer) do |action|
    now.instance_eval do
      @outer = action
      if @outer&&(not @outer.next.running?)
        @outer.values{|*args|@values = args}
        @ret.call
      end
    end
  end
  define_singleton_method(:turn_to) do |action|
    now.instance_eval do
      cencal = @cencal
      @cencal = lambda do
        action.cencal
        cencal.exec if cencal
      end
      loop do
        action.values do |*args|
          @values = args
          @ret.call
        end unless action.next.running?
        Action.pause
      end
    end
  end
end