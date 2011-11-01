module Twostroke::Runtime
  class VM::Frame
    attr_reader :vm, :insns, :stack, :sp_stack, :catch_stack, :finally_stack, :exception, :ip, :scope
    
    def initialize(vm, section, callee = nil)
      @vm = vm
      @section = section
      @insns = vm.bytecode[section]
      @callee = callee
    end
    
    def execute(scope, this = nil, args = [])
      @scope = scope || Scope.new(vm.global_scope)
      @stack = []
      @sp_stack = []
      @catch_stack = []
      @finally_stack = []
      @ip = 0
      @return = false
      @this = this || @scope.global_scope.root_object
      @args = args
      
      until @return
        ins, arg = *insns[ip]
        st = @stack.size
        @ip += 1
        if respond_to? ins
          if @exception = catch(:exception) { public_send ins, arg; nil }
            throw :exception, @exception if catch_stack.empty?
            @ip = catch_stack.last
          end
        else
          error! "unknown instruction #{ins}"
        end
      end
      
      stack.last
    end
    
    define_method ".local" do |arg|
      scope.declare arg.intern
    end
    
    define_method ".arg" do |arg|
      scope.declare arg.intern
      scope.set_var arg.intern, @args.shift || Types::Undefined.new
    end
    
    define_method ".catch" do |arg|
      scope.declare arg.intern
      scope.set_var arg.intern, @exception
    end
    
    ## instructions
    
    def push(arg)
      if arg.is_a? Symbol
        stack.push scope.get_var(arg)
      elsif arg.is_a?(Fixnum) || arg.is_a?(Float)
        stack.push Types::Number.new(arg)
      elsif arg.is_a?(Bignum)
        stack.push Types::Number.new(arg.to_f)
      elsif arg.is_a?(String)
        stack.push Types::String.new(arg)
      else
        error! "bad argument to push instruction"
      end
    end
    
    def call(arg)
      args = []
      arg.times { args.unshift @stack.pop }
      fun = stack.pop
      error! "TypeError: called_non_callable" unless fun.respond_to?(:call) #@TODO
      stack.push fun.call(scope, scope.global_scope.root_object, args)
    end
    
    def thiscall(arg)
      args = []
      arg.times { args.unshift stack.pop }
      fun = stack.pop
      error! "TypeError: called_non_callable" unless fun.respond_to?(:call) #@TODO
      stack.push fun.call(scope, Types.to_object(stack.pop), args)
    end
    
    def newcall(arg)
      args = []
      arg.times { args.unshift @stack.pop }
      fun = stack.pop
      error! "TypeError: called_non_callable" unless fun.respond_to?(:call) #@TODO
      obj = Types::Object.new
      obj.construct prototype: fun.get("prototype"), _class: fun.name do
        retn = fun.call(scope, obj, args)
        if retn.is_a?(Types::Undefined)
          stack.push obj
        else
          stack.push retn
        end
      end
    end
    
    def dup(arg)
      n = arg || 1
      stack.push *stack[-n..-1]
    end
    
    def member(arg)
      stack.push Types.to_object(stack.pop).get(arg.to_s)
    end
    
    def set(arg)
      scope.set_var arg, stack.last
    end
    
    def setprop(arg)
      val = stack.pop
      obj = stack.pop
      obj.put arg.to_s, val
      stack.push val
    end
    
    def ret(arg)
      if finally_stack.empty?
        @return = true
      else
        @ip = finally_stack.last
      end
    end
    
    def _throw(arg)
      throw :exception, stack.pop
      #raise ExceptionCarrier.new(stack.pop)
    end
    
    def eq(arg)
      ## javascript is fucked
      error! "== not yet implemented, please use === and convert types accordingly"
    end
    
    def seq(arg)
      a = stack.pop
      b = stack.pop
      if a.class == b.class
        stack.push Types::Boolean.new(a === b)
      else
        # @TODO: coerce
        raise "@TODO"
      end
    end
    
    def null(arg)
      stack.push Types::Null.new
    end
    
    def true(arg)
      stack.push Types::Boolean.new(true)
    end
    
    def false(arg)
      stack.push Types::Boolean.new(false)
    end
    
    def jmp(arg)
      @ip = arg.to_i
    end
    
    def jif(arg)
      if Types.is_falsy stack.pop
        @ip = arg.to_i
      end
    end
    
    def jit(arg)
      if Types.is_truthy stack.pop
        @ip = arg.to_i
      end
    end
    
    def not(arg)
      stack.push Types::Boolean.new(Types.is_falsy(stack.pop))
    end
    
    def inc(arg)
      stack.push Types::Number.new(Types.to_number(stack.pop).number + 1)
    end
    
    def dec(arg)
      stack.push Types::Number.new(Types.to_number(stack.pop).number - 1)
    end
    
    def pop(arg)
      stack.pop
    end
    
    def index(arg)
      index = Types.to_string(stack.pop).string
      stack.push(Types.to_object(stack.pop).get(index) || Types::Undefined.new)
    end
    
    def array(arg)
      args = []
      arg.times { args.unshift stack.pop }
      stack.push Types::Array.new(args)
    end
    
    def undefined(arg)
      stack.push Types::Undefined.new
    end
    
    def add(arg)
      r = stack.pop
      l = stack.pop
      unless l && r
        require 'pry'
        pry binding
      end
      right = Types.to_primitive r
      left = Types.to_primitive l
      
      if left.is_a?(Types::String) || right.is_a?(Types::String)
        stack.push Types::String.new(Types.to_string(left).string + Types.to_string(right).string)
      else
        stack.push Types::Number.new(Types.to_number(left).number + Types.to_number(right).number)
      end
    end
    
    def sub(arg)
      right = Types.to_number(stack.pop).number
      left = Types.to_number(stack.pop).number
      stack.push Types::Number.new(left - right)
    end
    
    def setindex(arg)
      val = stack.pop
      index = Types.to_string(stack.pop).string
      Types.to_object(stack.pop).put index, val
      stack.push val
    end
    
    def lt(arg)
      comparison_oper :<
    end
    
    def lte(arg)
      comparison_oper :<=
    end
    
    def gt(arg)
      comparison_oper :>
    end
    
    def gte(arg)
      comparison_oper :>=
    end
    
    def typeof(arg)
      stack.push Types::String.new(stack.pop.typeof)
    end
    
    def close(arg)
      arguments = vm.bytecode[arg].take_while { |ins,arg| ins == :".arg" }.map(&:last).map(&:to_s)
      fun = Types::Function.new(->(outer_scope, this, args) { VM::Frame.new(vm, arg, fun).execute(scope.close, this, args) }, "...", "", arguments)
      stack.push fun
    end
    
    def callee(arg)
      stack.push @callee
    end
    
    def object(arg)
      obj = Types::Object.new
      kvs = []
      arg.reverse_each { |a| kvs << [a, stack.pop] }
      kvs.reverse_each { |kv| obj.put kv[0].to_s, kv[1] }
      stack.push obj
    end
    
    def negate(arg)
      stack.push Types::Number.new(-Types.to_number(stack.pop).number)
    end
    
    def pushsp(arg)
      sp_stack.push stack.size
    end
    
    def popsp(arg)
      @stack = stack[0...sp_stack.pop]
    end
    
    def pushcatch(arg)
      catch_stack.push arg
    end
    
    def popcatch(arg)
      catch_stack.pop
    end
    
    def pushfinally(arg)
      finally_stack.push arg
    end
    
    def popfinally(arg)
      finally_stack.pop
    end
    
    def this(arg)
      stack.push @this
    end
    
  private
    def comparison_oper(op)
      right = Types.to_primitive stack.pop
      left = Types.to_primitive stack.pop
      
      if left.is_a?(Types::String) && right.is_a?(Types::String)
        stack.push Types::Boolean.new(left.string.send op, right.string)
      else
        stack.push Types::Boolean.new(Types.to_number(left).number.send op, Types.to_number(right).number)
      end
    end
  
    def error!(msg)
      vm.send :error!, "#{msg} (at #{@section}+#{@ip - 1})"
    end
  end
end