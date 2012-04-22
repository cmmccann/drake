classdef ConstantControl < SmoothRobotLibSystem
% Trivial control class that always outputs a constant u.
  
  methods
    function obj = ConstantControl(const_y)
      % Create ConstantControl object by specifying y.
      obj = obj@SmoothRobotLibSystem(0,0,0,length(const_y),false,true);
      obj.const_y = const_y;
    end
    function y = output(obj,~,~,~)
      % Implement control.
      y = obj.const_y;
    end
  end
  
  properties
    const_y;
  end
  
end