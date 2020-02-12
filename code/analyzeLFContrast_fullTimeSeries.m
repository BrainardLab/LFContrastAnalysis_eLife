function [modelResponseStructIAMP, modelResponseStructQCM, thePacketIAMP, thePacketQCM] = analyzeLFContrast_fullTimeSeries(subjId,varargin)
% Takes in a time series and chops it up into n runs.
%
% Syntax:
%    [thePackets] = chopUpTimeCourse(timeCoursePacket,numChops,varargin)
%
% Description:
%    Takes in a time series and chops it up nto n runs of equal length.
%
% Inputs:
%    timeCoursePacket           - The time course packet to be chopped up
%                                 A struct with "timebase" and "values"
%                                 subfeilds.
%    numChops                   - Number of cut to be made
%
% Outputs:
%    choppedTC                  - A cell array of the original packet
%                                 chopped into nunChops smaller packets
%                                 with a "values" and "timebase
% Optional key/value pairs:
%    - none for now

% MAB 12/22/19 created it

p = inputParser; p.KeepUnmatched = true; p.PartialMatching = false;
p.addRequired('subjId',@isstr);
p.addParameter('showPlot',@islogical);
p.parse(subjId,varargin{:});


% Get subject specific params: 'LZ23', 'KAS25', 'AP26'
analysisParams = getSubjectParams(subjId);

% set the preprocessing method that was used to ananlyze the data.
analysisParams.preproc = 'hcp';

% turn on or off plotting
analysisParams.showPlots = true;

% Set the option to use simulated data from known parameters
analysisParams.analysisSimulate = false;
% Set which model to use to generate the
analysisParams.simulationMethod = 'QCM'; % 'QCM' or 'IAMP'

%set the HRF
load(fullfile(getpref('LFContrastAnalysis','melaAnalysisPath'),'LFContrastAnalysis','subjectHRFs',analysisParams.expSubjID,[analysisParams.expSubjID '_eventGain_results.mat']));
xBase = zeros(1,analysisParams.expLengthTR);
xBase(1:length(results.hrf')) = results.hrf';
analysisParams.HRF.values = xBase;
analysisParams.HRF.timebase =   analysisParams.timebase*1000;
scaleVal = trapz(analysisParams.HRF.timebase,analysisParams.HRF.values);
analysisParams.HRF.values = analysisParams.HRF.values./scaleVal;


%% Get stimulus design matrix for the entire measurment set (session 1 and session 2 pair)
[stimCells] = makeStimMatrices(subjId);

% Get the time course data
[fullCleanData, analysisParams] = getTimeCourse_hcp(analysisParams);

% Pull out the median time courses
[analysisParams, iampTimeCoursePacketPocket, iampOBJ, iampParams, iampResponses, rawTC] = fit_IAMP(analysisParams,fullCleanData,'concatAndFit', true);

% Concat the stim matrices and time courses
theSignal = [rawTC{1}.values, rawTC{2}.values];
theStimIAMP   =  cat(2, stimCells{:});

% Create timebase
numTimePoints = length(theSignal);
timebase = linspace(0,(numTimePoints-1)*analysisParams.TR,numTimePoints)*1000;

% Create the packet
thePacketIAMP.response.values   = theSignal;
thePacketIAMP.response.timebase = timebase;

thePacketIAMP.stimulus.values   = theStimIAMP;
thePacketIAMP.stimulus.timebase = timebase;
% the kernel
kernelVec = zeros(size(timebase));
kernelVec(1:length(analysisParams.HRF.values)) = analysisParams.HRF.values;
thePacketIAMP.kernel.values = kernelVec;
thePacketIAMP.kernel.timebase = timebase;
% packet meta data
thePacketIAMP.metaData = [];

% Construct the model object
iampOBJ = tfeIAMP('verbosity','none');

% fit the IAMP model
defaultParamsInfo.nInstances = size(thePacketIAMP.stimulus.values,1);
[paramsFit,fVal,IAMPResponses] = iampOBJ.fitResponse(thePacketIAMP,...
    'defaultParamsInfo', defaultParamsInfo, 'searchMethod','linearRegression');
% generate time course from params fit and stim struct
modelResponseStructIAMP = iampOBJ.computeResponse(paramsFit,thePacketIAMP.stimulus,thePacketIAMP.kernel);

% Calculate R^2
corrValsIAMP = [modelResponseStructIAMP.values',thePacketIAMP.response.values'];
rSquaredIAMP = corr(corrValsIAMP).^2;


%% Do the QCM fit!
% Get directon/contrast form of time course and IAMP crf packet pockets.
directionTimeCoursePacketPocket = makeDirectionTimeCoursePacketPocket(iampTimeCoursePacketPocket);
theStimQCM   =  [directionTimeCoursePacketPocket{1}.stimulus.values,directionTimeCoursePacketPocket{2}.stimulus.values];

% Create the packet
thePacketQCM.response = thePacketIAMP.response;

thePacketQCM.stimulus.values   = theStimQCM;
thePacketQCM.stimulus.timebase = timebase;
% the kernel
thePacketQCM.kernel = thePacketIAMP.kernel;
% packet meta data
thePacketQCM.metaData = [];

% generate time course from params fit and stim struct
[qcmOBJ,qcmParams] = fitDirectionModel(analysisParams, 'qcmFit', {thePacketQCM});
modelResponseStructQCM = qcmOBJ.computeResponse(qcmParams{1},thePacketQCM.stimulus,thePacketQCM.kernel);

% plot it
if p.Results.showPlot == true
    figure;hold on
    plot(thePacketIAMP.response.timebase,thePacketIAMP.response.values,'k','LineWidth',2);
    plot(modelResponseStructIAMP.timebase,modelResponseStructIAMP.values,'r','LineWidth',2);
    plot(modelResponseStructQCM.timebase,modelResponseStructQCM.values,'g','LineWidth',2);
    legend('Time Course','IAMP','QCM')
    title(sprintf('R sqaured IAMP: %s R squared QCM: %s',num2str(rSquaredIAMP(2)),num2str(rSquaredQCM(2))));
end

end