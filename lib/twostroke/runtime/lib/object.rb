module Twostroke::Runtime
  Lib.register do |scope|
    proto = Types::Object.new
  
    obj = Types::Function.new(->(scope, this, args) {
        if args.length.zero? || args[0].is_a?(Types::Null) || args[0].is_a?(Types::Undefined)
          Types::Object.new
        else
          Types.to_object(args[0])
        end
      }, nil, "Object", [])
    #obj.prototype is Function, lets set its prototype to proto
    obj.prototype.prototype = proto
    obj.proto_put "prototype", proto
    scope.set_var "Object", obj
    
    proto.proto_put "toString", Types::Function.new(->(scope, this, args) {
      if this.is_a? Types::Primitive
        Types.to_string(this).string
      else
        Types::String.new "[object #{this._class ? this._class.name : "Object"}]"
      end
    }, nil, "toString", [])
    proto.proto_put "valueOf", Types::Function.new(->(scope, this, args) { this }, nil, "valueOf", [])
    proto.proto_put "hasOwnProperty", Types::Function.new(->(scope, this, args) {
      Types::Boolean.new Types.to_object(this || Types::Undefined.new).has_own_property(Types.to_string(args[0] || Types::Undefined.new).string)
    }, nil, "hasOwnProperty", [])
    proto.proto_put "isPrototypeOf", Types::Function.new(->(scope, this, args) {
      if args[0].is_a? Types::Object
        proto = args[0].prototype
        this = Types.to_object(this || Types::Undefined.new)
        while proto.is_a?(Types::Object)
          return Types::Boolean.true if this == proto
          proto = proto.prototype
        end
      end
      Types::Boolean.false
    }, nil, "isPrototypeOf", [])
    proto.proto_put "propertyIsEnumerable", Types::Function.new(->(scope, this, args) {
      this = Types.to_object(this || Types::Undefined.new)
      prop = Types.to_string(args[0] || Types::Undefined.new).string
      if this.has_accessor(prop)
        Types::Boolean.new this.accessors[prop][:enumerable]
      elsif this.has_property(prop)
        Types::Boolean.true
      else
        Types::Boolean.false
      end
    }, nil, "propertyIsEnumerable", [])
    
    Types::Object.set_global_prototype proto
    Types::Object.define_singleton_method(:constructor_function) { obj }
    scope.global_scope.root_object.prototype = proto
  end
end