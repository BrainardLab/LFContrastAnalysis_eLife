function [] = analyzeLFContrast_crossValidate(subjId)

display(['STARTING - Cross Validating: ',subjId])
% Load the subject relevant info
analysisParams = getSubjectParams(subjId);
analysisParams.runNRModels = true;

analysisParams.preproc = 'hcp';

analysisParams.saveFigs = true;

% bandpass the signal
analysisParams.highpass = false;

%turn on or off plotting
analysisParams.showPlots = true;
qcmColor  = [0.4078, 0.2784, 0.5765];
iampColor = [0.8902, 0.6235, 0.5529];
lcmColor  = [0.7 , .12, .1];
%% Load the relevant data (SDM, HRF, TC)

%set the HRF
[analysisParams] = loadHRF(analysisParams);

if analysisParams.highpass
    analysisParams.HRF.values = highpass(analysisParams.HRF.values ,5/288,1/.8);
end

% Load the time course
[fullCleanData, analysisParams] = getTimeCourse_hcp(analysisParams);

% Get a packet for each run (1-20)
[analysisParams, iampTimeCoursePacketPocket] = generateRunPackets(analysisParams, fullCleanData,'highpass',analysisParams.highpass);

%% Generate a cell array of concat train packets and a corresponding cell
%  array of concat test packets
[iampTestPackets, iampTrainPackets,leaveOutPairs] = concatPackets_crossVal(analysisParams, iampTimeCoursePacketPocket);

% Create the time Course packet
% Get directon/contrast form of time course and IAMP crf packet pockets.
qcmTrainPackets = makeDirectionTimeCoursePacketPocket(iampTrainPackets);
qcmTestPackets = makeDirectionTimeCoursePacketPocket(iampTestPackets);

% Construct the model object
iampOBJ = tfeIAMP('verbosity','none');
LCMObj = tfeLCMDirection('verbosity','none','dimension',2);

% init vars
timeCoursePlot.qcm = [];
timeCoursePlot.qcmLock = [];
timeCoursePlot.lcm = [];
timeCoursePlot.IAMP = [];
timeCoursePlot.timecourse = [];
rSquaredQcm = [];
rSquaredIamp = [];
count = 0;

% loop over cross-val iterations
for ii = 1:length(iampTrainPackets)
    
    %% FIT THE TIME COURSE
    theIampTrainPacket = iampTrainPackets{ii};
    theIampTestPacket = iampTestPackets{ii};
    theQcmTrainPacket = qcmTrainPackets{ii};
    theQcmTestPacket = qcmTestPackets{ii};
    
    
    % fit the IAMP model
    defaultParamsInfo.nInstances = size(theIampTrainPacket.stimulus.values,1);
    [iampParams,fVal,iampResponses] = iampOBJ.fitResponse(theIampTrainPacket,...
        'defaultParamsInfo', defaultParamsInfo, 'searchMethod','linearRegression');
    
    
    % run NR models if set to true
    if analysisParams.runNRModels
        % Fit the CRF -- { } is because this expects a cell
        [nrCrfOBJ,nrCrfParams] = fitDirectionModel(analysisParams, 'nrFit', {theQcmTrainPacket},'talkToMe',false);
        nr = responseFromPacket('nrFullTCPred', analysisParams, nrCrfParams{1}, {theQcmTestPacket}, 'plotColor', [0, 0, 1]);
        
        % Fit the CRF with the NR common amplitude -- { } is because this expects a cell
        [~,nrCrfParamsAmp] = fitDirectionModel(analysisParams, 'nrFit', {theQcmTrainPacket}, 'commonAmp', true,'talkToMe',false);
        nrAmp = responseFromPacket('nrFullTCPred', analysisParams, nrCrfParamsAmp{1}, {theQcmTestPacket}, 'plotColor', [0, 0, 1]);
        
        % Fit the CRF with the NR common Exponent -- { } iPs because this expects a cell
        [~,nrCrfParamsExp] = fitDirectionModel(analysisParams, 'nrFit', {theQcmTrainPacket}, 'commonExp', true,'talkToMe',false);
        nrExp = responseFromPacket('nrFullTCPred', analysisParams, nrCrfParamsExp{1}, {theQcmTestPacket}, 'plotColor', [0, .33, 1]);
        
        % Fit the CRF with the NR common amplitude, and exponent  -- { } is because this expects a cell
        [~,nrCrfParamsAmpExp] = fitDirectionModel(analysisParams, 'nrFit', {theQcmTrainPacket}, 'commonAmp', true, 'commonExp', true,'talkToMe',false);
        nrAmpExp = responseFromPacket('nrFullTCPred', analysisParams, nrCrfParamsAmpExp{1}, {theQcmTestPacket}, 'plotColor', [0, .66, 1]);
    end
    
    % Fit the time course with the LCM
    [fitLCMParams,fVal,fitResponseStructLCM] = LCMObj.fitResponse(theQcmTrainPacket);
    
    % Fit the time course with the QCM -- { } is because this expects a cell
    [qcmTcOBJ,qcmTcParams] = fitDirectionModel(analysisParams, 'qcmFit', {theQcmTrainPacket},'fitErrorScalar',1000,'talkToMe',false);
    
    % Fit the time course with the QCM where the angel is locked to zero-- { } is because this expects a cell
    [qcmLockedTcOBJ,qcmLockedTcParams] = fitDirectionModel(analysisParams, 'qcmFitAngelLockedToZero', {theQcmTrainPacket},'fitErrorScalar',1000,'talkToMe',false);
    
    % Get the time course predicitions from the QCM params 
    qcmTimeCourse = responseFromPacket('qcmPred', analysisParams, qcmTcParams{1}, {theQcmTestPacket}, 'plotColor', qcmColor);
    qcmChopped = chopUpTimeCourse(qcmTimeCourse{1},2);
    [timeCoursePlot.qcm] = [timeCoursePlot.qcm,qcmChopped];
    
    % Get the time course predicitions from the QCM Locked params 
    qcmLockedTimeCourse = responseFromPacket('qcmPred', analysisParams, qcmLockedTcParams{1}, {theQcmTestPacket}, 'plotColor', qcmColor);
    qcmLockedChopped = chopUpTimeCourse(qcmLockedTimeCourse{1},2);
    [timeCoursePlot.qcmLock] = [timeCoursePlot.qcmLock,qcmLockedChopped];
    
    % LCM
    LCMResponseStruct = LCMObj.computeResponse(fitLCMParams,theQcmTestPacket.stimulus,theQcmTestPacket.kernel,'AddNoise',false);
    LCMResponseStruct.plotColor = lcmColor;
    lcmChopped   = chopUpTimeCourse(LCMResponseStruct,20);
    [timeCoursePlot.lcm] = [timeCoursePlot.lcm,lcmChopped];
    
    iampTimeCourse = responseFromPacket('IAMP', analysisParams, iampParams, theIampTestPacket, 'plotColor', iampColor);
    iampChopped = chopUpTimeCourse(iampTimeCourse,2);
    [timeCoursePlot.IAMP] = [timeCoursePlot.IAMP, iampChopped];
    
    theTimeCourse= theQcmTestPacket.response;
    theTimeCourse.plotColor =[0, 0, 0];
    timeCourseChopped = chopUpTimeCourse(theTimeCourse,2);
    [timeCoursePlot.timecourse] = [timeCoursePlot.timecourse, timeCourseChopped];
    
    %% Calc R squared
    % put correltation values on each iteration
    
    % QCM R^2
    qcmCorrVec =  [theTimeCourse.values',qcmTimeCourse{1}.values'];
    qcmCorrVals = corrcoef(qcmCorrVec(:,1),qcmCorrVec(:,2),'rows','complete').^2;
    rSquaredQcm(ii) = qcmCorrVals(1,2);
    
    % QCM Locked R^2
    qcmLockedCorrVec =  [theTimeCourse.values',qcmLockedTimeCourse{1}.values'];
    qcmLockedCorrVals = corrcoef(qcmLockedCorrVec(:,1),qcmLockedCorrVec(:,2),'rows','complete').^2;
    rSquaredQcmLocked(ii) = qcmLockedCorrVals(1,2);
    
    % LCM R^2
    lcmCorrVec =  [theTimeCourse.values',LCMResponseStruct.values'];
    lcmCorrVals = corrcoef(lcmCorrVec(:,1),lcmCorrVec(:,2),'rows','complete').^2;
    rSquaredLcm(ii) = lcmCorrVals(1,2);
    
    % GLM R^2
    iampCorrVec =  [theTimeCourse.values',iampTimeCourse.values'];
    iampCorrVals = corrcoef(iampCorrVec(:,1),iampCorrVec(:,2),'rows','complete').^2;
    rSquaredIamp(ii) = iampCorrVals(1,2);
    
    if analysisParams.runNRModels
        % NR R^2
        nrCorrVec =  [theTimeCourse.values',nr{1}.values'];
        nrCorrVals = corrcoef(nrCorrVec(:,1),nrCorrVec(:,2),'rows','complete').^2;
        rSquaredNr(ii) = nrCorrVals(1,2);
        
        % NR common amplitude R^2
        nrAmpCorrVec =  [theTimeCourse.values',nrAmp{1}.values'];
        nrAmpCorrVals = corrcoef(nrAmpCorrVec(:,1),nrAmpCorrVec(:,2),'rows','complete').^2;
        rSquaredNrAmp(ii) = nrAmpCorrVals(1,2);
        
        % NR common Exponent R^2
        nrExpCorrVec =  [theTimeCourse.values',nrExp{1}.values'];
        nrExpCorrVals = corrcoef(nrExpCorrVec(:,1),nrExpCorrVec(:,2),'rows','complete').^2;
        rSquaredNrExp(ii) = nrExpCorrVals(1,2);
        
        % NR common amplitude, and exponent R^2
        nrAmpExpCorrVec =  [theTimeCourse.values',nrAmpExp{1}.values'];
        nrAmpExpCorrVals = corrcoef(nrAmpExpCorrVec(:,1),nrAmpExpCorrVec(:,2),'rows','complete').^2;
        rSquaredNrAmpExp(ii) = nrAmpExpCorrVals(1,2);
    end
    
end

% calculate the mean R^2 for each model
rSquaredQcmMean      = mean(rSquaredQcm);
rSquaredQcmLockedMean = mean(rSquaredQcmLocked);
rSquaredLcmMean      = mean(rSquaredLcm);
rSquaredIampMean     = mean(rSquaredIamp);
rSquaredNrMean       = mean(rSquaredNr);
rSquaredNrAmpMean    = mean(rSquaredNrAmp);
rSquaredNrExpMean    = mean(rSquaredNrExp);
rSquaredNrAmpExpMean = mean(rSquaredNrAmpExp);

% get error bars around the mean
qcmRsquaredCI      = std(rSquaredQcm)./sqrt(lenght(rSquaredQcm));
qcmLockedRsquaredCI = std(rSquaredQcmLocked)./sqrt(lenght(rSquaredQcmLocked));
lcmRsquaredCI      = std(rSquaredLcm)./sqrt(lenght(rSquaredLcm));
iampRsquaredCI     = std(rSquaredIamp)./sqrt(lenght(rSquaredIamp));
nrRsquaredCI       = std(rSquaredNr)./sqrt(lenght(rSquaredNr));
nrAmpRsquaredCI    = std(rSquaredNrAmp)./sqrt(lenght(rSquaredNrAmp));
nrExpRsquaredCI    = std(rSquaredNrExp)./sqrt(lenght(rSquaredNrExp));
nrAmpExpRsquaredCI = std(rSquaredNrAmpExp)./sqrt(lenght(rSquaredNrAmpExp));

%% Plot it
crossValR2 = figure; hold on;
set(gca,'Box', 'off','linewidth',3,'FontSize',12);
X = categorical({'GLM','NR','NR Amp','NR Exp','NR AmpExp','LCM','QCM','QCM locked'});
X = reordercats(X,{'GLM','NR','NR Amp','NR Exp','NR AmpExp','LCM','QCM','QCM locked'});
b = bar(X,[rSquaredIampMean;rSquaredNrMean;rSquaredNrAmpMean;rSquaredNrExpMean;rSquaredNrAmpExpMean;rSquaredLcmMean;rSquaredQcmMean;rSquaredQcmLockedMean]);
er = errorbar(X,[rSquaredIampMean;rSquaredNrMean;rSquaredNrAmpMean;rSquaredNrExpMean;rSquaredNrAmpExpMean;rSquaredLcmMean;rSquaredQcmMean;rSquaredQcmLockedMean],...
    [iampRsquaredCI(2), nrRsquaredCI(2),nrAmpRsquaredCI(2),nrExpRsquaredCI(2),nrAmpExpRsquaredCI(2), lcmRsquaredCI(2), qcmRsquaredCI(2), qcmLockedRsquaredCI(2)], ...
    [iampRsquaredCI(1), nrRsquaredCI(1),nrAmpRsquaredCI(1),nrExpRsquaredCI(1),nrAmpExpRsquaredCI(1), lcmRsquaredCI(1), qcmRsquaredCI(1), qcmLockedRsquaredCI(1)]);
er.Color = [0 0 0];
er.LineStyle = 'none';
er.LineWidth = 2;
b.FaceColor = 'flat';
b.CData(1,:) = iampColor;
b.CData(2,:) = [98,189,105]./255;
b.CData(3,:) = [90,171,97]./255;
b.CData(4,:) = [53,136,86]./255;
b.CData(5,:) = [37, 82, 59]./255;
b.CData(6,:) = lcmColor;
b.CData(7,:) = qcmColor;
b.CData(8,:) = qcmColor-.16;
b.EdgeColor = [0,0,0];
b.LineWidth = 2;
hXLabel = xlabel('Models');
hYLabel = ylabel('R^{2}');
hTitle  = title('Cross Validated R^{2}');
set([hTitle, hXLabel, hYLabel],'FontName', 'Helvetica');
set([hXLabel, hYLabel,],'FontSize', 14);
set( hTitle, 'FontSize', 14,'FontWeight' , 'bold');
ylim([0,1])
set(gca,'TickDir', 'out');
set(gcf, 'Color', 'white' );

modelTxtQcm   = ['{QCM: ' num2str(round(rSquaredQcmMean,2))...
    ' CI [' num2str(round(qcmRsquaredUpLow(2),2)) ', ' num2str(round(qcmRsquaredUpLow(1),2)) ']}'];
modelTxtIamp  = ['{GLM: ' num2str(round(rSquaredIampMean,2))...
    ' CI [' num2str(round(iampRsquaredUpLow(2),2)) ', ' num2str(round(iampRsquaredUpLow(1),2)) ']}'];
modelTxtNr   = ['{NR: ' num2str(round(rSquaredNrMean,2))...
    ' CI [' num2str(round(nrRsquaredUpLow(2),2)) ', ' num2str(round(nrRsquaredUpLow(1),2)) ']}'];
modelTxtNrAmp  = ['{NR Amp: ' num2str(round(rSquaredNrAmpMean,2))...
    ' CI [' num2str(round(nrAmpRsquaredUpLow(2),2)) ', ' num2str(round(nrAmpRsquaredUpLow(1),2)) ']}'];
modelTxtNrExp   = ['{NR Exp: ' num2str(round(rSquaredNrExpMean,2))...
    ' CI [' num2str(round(nrExpRsquaredUpLow(2),2)) ', ' num2str(round(nrExpRsquaredUpLow(1),2)) ']}'];
modelTxtNrAmpExp  = ['{NR AmpExp: ' num2str(round(rSquaredNrAmpExpMean,2))...
    ' CI [' num2str(round(nrAmpExpRsquaredUpLow(2),2)) ', ' num2str(round(nrAmpExpRsquaredUpLow(1),2)) ']}'];
modelTxtLcm   = ['{LCM: ' num2str(round(rSquaredLcmMean,2))...
    ' CI [' num2str(round(lcmRsquaredUpLow(2),2)) ', ' num2str(round(lcmRsquaredUpLow(1),2)) ']}'];
modelTxtQcmLock   = ['{QCM Locked: ' num2str(round(rSquaredQcmLockedMean,2))...
    ' CI [' num2str(round(qcmLockedRsquaredUpLow(2),2)) ', ' num2str(round(qcmLockedRsquaredUpLow(1),2)) ']}'];

theTextHandle = text(gca, .59,.95 , modelTxtIamp, 'Interpreter', 'latex');
set(theTextHandle,'FontSize', 12, 'Color', [0.3 0.3 0.3], 'BackgroundColor', [1 1 1]);

theTextHandle = text(gca, .59,0.87, modelTxtNr, 'Interpreter', 'latex');
set(theTextHandle,'FontSize', 12, 'Color', [0.3 0.3 0.3], 'BackgroundColor', [1 1 1]);

theTextHandle = text(gca, .59,0.79, modelTxtNrAmp, 'Interpreter', 'latex');
set(theTextHandle,'FontSize', 12, 'Color', [0.3 0.3 0.3], 'BackgroundColor', [1 1 1]);

theTextHandle = text(gca, .59,0.71, modelTxtNrExp, 'Interpreter', 'latex');
set(theTextHandle,'FontSize', 12, 'Color', [0.3 0.3 0.3], 'BackgroundColor', [1 1 1]);

theTextHandle = text(gca, 4,0.95, modelTxtNrAmpExp, 'Interpreter', 'latex');
set(theTextHandle,'FontSize', 12, 'Color', [0.3 0.3 0.3], 'BackgroundColor', [1 1 1]);

theTextHandle = text(gca, 4,0.87, modelTxtLcm, 'Interpreter', 'latex');
set(theTextHandle,'FontSize', 12, 'Color', [0.3 0.3 0.3], 'BackgroundColor', [1 1 1]);

theTextHandle = text(gca, 4,0.79, modelTxtQcm, 'Interpreter', 'latex');
set(theTextHandle,'FontSize', 12, 'Color', [0.3 0.3 0.3], 'BackgroundColor', [1 1 1]);

theTextHandle = text(gca, 4,0.71, modelTxtQcmLock, 'Interpreter', 'latex');
set(theTextHandle,'FontSize', 12, 'Color', [0.3 0.3 0.3], 'BackgroundColor', [1 1 1]);
%% Save it
if analysisParams.saveFigs
    set(crossValR2, 'Renderer', 'Painters');
    figureSizeInches = [6 5.5];
    set(crossValR2, 'PaperUnits', 'inches');
    set(crossValR2, 'PaperSize',figureSizeInches);
    set(crossValR2, 'PaperPosition', [0 0 figureSizeInches(1) figureSizeInches(2)]);
    figNameEllipseNonlin = fullfile(getpref(analysisParams.projectName,'figureSavePath'),analysisParams.expSubjID, ...
        [analysisParams.expSubjID,'_Cross_Val_R2_AllModels_' analysisParams.sessionNickname '_' analysisParams.preproc '.pdf']);
    print(crossValR2, figNameEllipseNonlin, '-dpdf', '-r300');
end
display(['COMPLETED: ',subjId])
end
