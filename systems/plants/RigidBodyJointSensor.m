classdef RigidBodyJointSensor < RigidBodySensor
  % outputs a (vector of) joint positions, given a mask specifying 
  % which DOF to include
  
  methods
    function obj = RigidBodyJointSensor(manip,robotnum)
      typecheck(manip,'RigidBodyManipulator');
      if (nargin<3) robotnum = 1; end
      obj.robotnum = robotnum;
    end
    
    function y = output(obj,manip,t,x,u)
      y=x(obj.dof_mask);
    end
    function fr = constructFrame(obj,manip)
      state_frame = manip.getStateFrame;
      c = getCoordinateNames(state_frame);
      fr = CoordinateFrame([manip.name{obj.robotnum},'JointPosition'],numel(obj.dof_mask),'p',c(obj.dof_mask));
    end
    function tf = isDirectFeedthrough(obj)
      tf=false;
    end
    
    function obj = compile(obj,manip)
      obj.dof_mask = [manip.body([manip.body.has_position_sensor] & [manip.body.robotnum]==obj.robotnum).dofnum];
    end
        
  end
  
  properties
    robotnum;
    dof_mask;
  end
end