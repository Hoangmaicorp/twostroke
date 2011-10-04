module Twostroke::AST
  [ :PostIncrement, :PreIncrement, :PostDecrement, :PreDecrement,
    :BinaryNot, :UnaryPlus, :Negation, :TypeOf, :Not ].each do |op|
      klass = Class.new Base do
        attr_accessor :value
      
        def collapse
          self.class.new value: value.collapse
        end
      end
      const_set op, klass
    end
end