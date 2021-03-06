function [ytraj,xtraj] = simulate(obj,tspan,x0,options)
% Simulates the dynamical system (using the simulink solvers)
%
% @param tspan a 1x2 vector of the form [t0 tf]
% @param x0 a vector of length(getNumStates) which contains the initial
% state (@default calls getInitialState())
%
% @option FixedStep   for fixed-step solver only, generate output at the FixedStep spaced time points
% @option OutputOption 'RefineOutputTimes' | 'AdditionalOutputTimes' | 'SpecifiedOutputTimes' 
%            For variable step solver only
% @option OutputTimes to generate output in the time sequence options.OutputTimes

if(exist('DCSFunction') ~=3)
    error('Sorry, it looks like you have not run make yet. Please run configure and make, then rerun drake.')
end

typecheck(tspan,'double');
if (length(tspan)<2) error('length(tspan) must be > 1'); end
if (nargin<4) options=struct([]); end
mdl = getModel(obj);

if (strcmp(get_param(mdl,'SimulationStatus'),'paused'))
  feval(mdl,[],[],[],'term');  % terminate model, in case it was still running before
end

pstruct = obj.simulink_params;
pstruct.StartTime = num2str(tspan(1));
pstruct.StopTime = num2str(tspan(end));
if(isfield(options,'FixedStep'))%if using fixed-step solver and want to generate output at a dt spaced time line.
    solver=get_param(mdl,'Solver');
    if(strcmp(solver,'ode1')||strcmp(solver,'ode2')||strcmp(solver,'ode3')||strcmp(solver,'ode4')||strcmp(solver,'ode5'))
        pstruct.FixedStep=num2str(options.FixedStep);
    else
        warning('FixedStep option can only be used for fixed-step solver');
    end
end
if (nargin>2) % handle initial conditions
  if (isa(x0,'Point'))
    x0 = double(x0.inFrame(obj.getStateFrame));
  else
    typecheck(x0,'double');
    sizecheck(x0,[obj.getStateFrame.dim,1]);
  end
  x0 = obj.stateVectorToStructure(x0);
  assignin('base',[mdl,'_x0'],x0);
  pstruct.InitialState = [mdl,'_x0'];
  pstruct.LoadInitialState = 'on';

  if (~isempty(find_system(mdl,'ClassName','InitialCondition')))
    warning('Your model appears to have an initial conditions block in it (e.g., from SimMechanics).  That block will overwrite any initial conditions that you pass in to simulate.');
  end
end

  function traj = makeSubTrajectory(t,y)
    if (length(t)<2) keyboard; end
    
    %% attempt to identify DT outputs, and avoid interpolating them (badly) as smooth polynomials
    ts = getSampleTime(obj);
    traj={}; idx={}; yidx=1:size(y,1);
    for i=1:size(ts,2)
      if (ts(1,i)>0) % then this is a DT sample time.  try to find outputs that update only on this sample time
        n = ceil((t-ts(2,i))/ts(1,i));  % counts 0 to N
        nidx=find([1;diff(n)]);
        ydiff = y(yidx,:)-y(yidx,nidx(n-n(1)+1));
        dtidx = yidx(all(abs(ydiff)<eps,2));  
        if (~isempty(dtidx))
          n=unique(n);
          tt=(n(2:end)-1)*ts(1,i)+ts(2,i);
          traj={traj{:}, PPTrajectory(zoh([t(1);tt+eps(tt);t(end)]',[y(dtidx,1),y(dtidx,nidx(2:end)),y(dtidx,end)]))};
          idx = {idx{:}, dtidx};
          yidx = setdiff(yidx,dtidx);
        end
      end
    end
    
    if (isempty(traj)) % only CT outputs
      traj = PPTrajectory(spline(t,y));
    elseif (~isempty(yidx)) % add the CT outputs and make MixedTrajectory
      traj = {traj{:},PPTrajectory(spline(t,y(yidx,:)))};
      idx = {idx{:}, yidx};
      traj = MixedTrajectory(traj,idx);
    end
    
  end

if (nargout>0)
  if (getNumOutputs(obj)<1) error('this dynamical system doesn''t have any outputs'); end
  
  pstruct.SaveFormat = 'StructureWithTime';
  pstruct.SaveTime = 'on';
  pstruct.TimeSaveName = 'tout';
  if (nargout>1)
    pstruct.SaveState = 'on';
  else
    pstruct.SaveState = 'off';
  end
  pstruct.StateSaveName = 'xout';
  pstruct.SaveOutput = 'on';
  pstruct.OutputSaveName = 'yout';
  pstruct.LimitDataPoints = 'off';
  %pstruct.SaveOnModelUpdate = 'false';
  %pstruct.AutoSaveOptions.SaveModelOnUpdate = 'false';
  %pstruct.AutoSaveOptions.SaveBackupOnVersionUpgrade = 'false';
  
  ts = getSampleTime(obj);
  isdiscrete = all(ts(1,:)>0);  % isDT asks for more:  must have only a single sample time
  
  if (~isdiscrete)
    pstruct.Refine = '3';  % shouldn't do anything for DT systems
  end
  
  %If we are using variable-step solver, and want to specify the output time
  if(isfield(options,'OutputOption'))
    %pstruct.OutputOption='SpecifiedOutputTimes';
    pstruct.OutputOption=options.OutputOption;
  end
  if(isfield(options,'OutputTimes'))
    pstruct.OutputTimes=['[',num2str(options.OutputTimes),']'];
  end
  
  simout = sim(mdl,pstruct);
  
  t = simout.get('tout');
  if (nargout>1) 
    xout=simout.get('xout');
    l = {xout.signals(:).label};
    x = [];
    if (obj.getNumDiscStates>0)
      x = [x;xout.signals(find(strcmp(l,'DSTATE'))).values'];
    end
    if (obj.getNumContStates>0)
      x = [x;xout.signals(find(strcmp(l,'CSTATE'))).values'];
    end
  end
  y = simout.get('yout').signals.values';

  if (isdiscrete)
    ytraj = DTTrajectory(t',y);
    ytraj = setOutputFrame(ytraj,obj.getOutputFrame);
    if (nargout>1)
      xtraj = DTTrajectory(t',x);
      xtraj = setOutputFrame(xtraj,obj.getStateFrame);
    end
  else
    % note: could make this more exact.  see comments in bug# 623.

    % find any zero-crossing events (they won't have the extra refine steps)
    zcs = find(diff(t)<1e-10);
    if (length(zcs)>0) % then we have a hybrid trajectory
      zcs = [0;zcs;length(t)];
      ypptraj={}; xpptraj={};
      
      for i=1:length(zcs)-1
        % compute indices of this segment
        inds = (zcs(i)+1):zcs(i+1);
        if (length(inds)<2) % successive zero crossings?
          % commands like this are useful for debugging here:
          %  plot(y(2,:),y(3,:),'.-',y(2,zcs(2:end)),y(3,zcs(2:end)),'r*')
          %  keyboard;
          warnOnce(obj.warning_manager,'Drake:DynamicalSystem:SuccessiveZeroCrossings','successive zero crossings');
          i=i+1;
          continue;
        end
        ypptraj = {ypptraj{:},makeSubTrajectory(t([max(inds(1)-1,1),inds(2:end)]),y(:,inds))};  % use time of zc instead of 1e-10 past it.
        ypptraj{end} = setOutputFrame(ypptraj{end},obj.getOutputFrame);
        if (nargout>1)
          xpptraj = {xpptraj{:},makeSubTrajectory(t([max(inds(1)-1,1),inds(2:end)]),x(:,inds))};
          xpptraj{end} = setOutputFrame(xpptraj{end},obj.getStateFrame);
        end
        i=i+1;
      end
      if (length(ypptraj)>1)
        ytraj = HybridTrajectory(ypptraj);
        if (nargout>1)
          xtraj = HybridTrajectory(xpptraj);
        end
      else
        ytraj = ypptraj{1};
        if (nargout>1)
          xtraj = xpptraj{1};
        end
      end
    else
      ytraj = makeSubTrajectory(t,y);
      ytraj = setOutputFrame(ytraj,obj.getOutputFrame);
      if (nargout>1)
        xtraj = makeSubTrajectory(t,x);
        xtraj = setOutputFrame(xtraj,obj.getStateFrame);
      end
    end
  end
else
  sim(mdl,pstruct);
end

end
