% Convert to NWB
%
% Run this script to convert derived data generated by the Brain-wide
% infra-slow dynamics study at UoL to the Neurodata Without Borders (NWB)
% file format.
%
% The script works by loading general, animal, and recording session
% metadata from nwbParams, nwbAnimalParams, nwbSessionParams, respectively.
% It then locates the derived data MAT files for each animal and converts
% them into derived data NWB files dividing the data per recording session.
% The derived data include spiking, waveform, pupil area size fluctuation,
% and total facial movement data.
%
% The conversion pipeline depends on the specific structure of derived data
% MAT files used in this study. The way the pipeline is organised is
% dictated by the fact that the conversion procedure was adopted late in
% the study. Ideally NWB file format should be adopted early in the study.
%
% You can use this pipeline to get an idea of how to convert your own
% ecephys data to the NWB file format to store spiking and behavioural
% data combined with some metadata.

cleanUp

% Load general NWB parameters
nwbParams

% Load animal-specific parameters
nwbAnimalParams

% Load session-specific parameters
nwbSessionParams

% Generate Matlab classes from NWB core schema files
generateCore;

% Generate NWB files for every recording session
if ~exist(animalDerivedDataFolderNWB, 'file')
  mkdir(animalDerivedDataFolderNWB) % Folder to store animal's converted NWB data
end
for iSess = 1:numel(sessionID)
  % Assign NWB file fields
  nwb = NwbFile( ...
    'session_description', sessionDescription{iSess},...
    'identifier', [animalID '_' sessionID{iSess}], ...
    'session_start_time', sessionStartTime{iSess}, ...
    'general_experimenter', experimenter, ... % optional
    'general_session_id', sessionID{iSess}, ... % optional
    'general_institution', institution, ... % optional
    'general_related_publications', publications, ... % optional
    'general_notes', sessionNotes{iSess}, ... % optional
    'general_lab', lab); % optional
  
  % Create subject object
  subject = types.core.Subject( ...
    'subject_id', animalID, ...
    'age', age, ...
    'description', description, ...
    'species', species, ...
    'sex', sex);
  nwb.general_subject = subject;
  
  % Create electrode tables: Info about each recording channel
  input.iElectrode = 1;
  input.electrodeDescription = electrodeDescription{iSess};
  input.electrodeManufacturer = electrodeManufacturer{iSess};
  input.nShanks = nShanks{iSess};
  input.nChannelsPerShank = nChannelsPerShank{iSess};
  input.electrodeLocation = electrodeLocation{iSess};
  input.electrodeCoordinates = electrodeCoordinates{iSess};
  input.sessionID = sessionID{iSess};
  input.electrodeLabel = electrodeLabel{iSess};
  tbl1 = createElectrodeTable(nwb, input);
  
  input.iElectrode = 2;
  tbl2 = createElectrodeTable(nwb, input);
  
  tbl = [tbl1; tbl2];
  electrode_table = util.table2nwb(tbl, 'all electrodes');
  nwb.general_extracellular_ephys_electrodes = electrode_table;
  
  % Load spike times from the MAT file
  [spikes, metadata, derivedData] = getNeuronexusSpikes(animalDerivedDataFile, animalID, sessionID{iSess}, tbl);
  [spike_times_vector, spike_times_index] = util.create_indexed_column(spikes);
  spike_times_vector.description = 'Session spike times';
  spike_times_index.description = 'Indices dividing spike times into units';
  
  % Load and reshape unit waveforms
  waveformsFile1 = [electrodeFolder{iSess}{1} filesep 'waveforms.mat'];
  if exist(waveformsFile1, 'file')
    waveformsProbe1 = load(waveformsFile1);
    [waveformMat1, waveformVecGrp1, waveformVec1, waveformMeans1] = reshapeWaveforms(waveformsProbe1, 1, metadata);
  else
    waveformsProbe1.maxWaveforms = [];
    waveformMat1 = []; waveformVecGrp1 = []; waveformVec1 = []'; waveformMeans1 = [];
  end
  waveformsFile2 = [electrodeFolder{iSess}{2} filesep 'waveforms.mat'];
  if exist(waveformsFile2, 'file')
    waveformsProbe2 = load(waveformsFile2);
    [waveformMat2, waveformVecGrp2, waveformVec2, waveformMeans2] = reshapeWaveforms(waveformsProbe2, 1, metadata);
  else
    waveformsProbe2.maxWaveforms = [];
    waveformMat2 = []; waveformVecGrp2 = []; waveformVec2 = []'; waveformMeans2 = [];
  end
  maxWaveforms = [waveformsProbe1.maxWaveforms; waveformsProbe2.maxWaveforms];
  waveformMat = [waveformMat1; waveformMat2];
  waveformVec = [waveformVec1; waveformVec2];
  waveformMeans = [waveformMeans1; waveformMeans2];
  
  % Create waveform indices
  % These indices are not used as our waveform array has a different form and meaning than the one used in the NWB file.
  % We only store mean waveforms on maximum amplitude channels.
  % More on ragged array indexing used in NWB files see https://nwb-schema.readthedocs.io/en/latest/format_description.html
  [waveforms, waveformIndex] = util.create_indexed_column(waveformVec');
  waveformIndexIndex1 = reshape(waveformIndex.data(1:size(waveformVec1,1)),nCh{iSess}{1},size(waveformVec1,1)/nCh{iSess}{1})';
  waveformIndexIndex = {};
  for iUnit = 1:size(waveformVecGrp1,1)
    waveformIndexIndex = [waveformIndexIndex; waveformIndexIndex1(iUnit,:)];
  end
  waveformIndexIndex2 = reshape(waveformIndex.data(size(waveformVec1,1)+1:end),nCh{iSess}{2},size(waveformVec2,1)/nCh{iSess}{2})';
  for iUnit = 1:size(waveformVecGrp2,1)
    waveformIndexIndex = [waveformIndexIndex; waveformIndexIndex2(iUnit,:)];
  end
  [inds, waveformIndexIndex] = util.create_indexed_column(waveformIndexIndex');
  
  % Store spiking and waveform data inside the nwb object
  % see https://neurodatawithoutborders.github.io/matnwb/doc/+types/+core/Units.html
  nwb.units = types.core.Units( ...
    'colnames', {'cluster_id','local_cluster_id','type',...
    'peak_channel_index','peak_channel_id',... % Provide the column order. All column names have to be defined below
    'local_peak_channel_id','rel_horz_pos','rel_vert_pos',...
    'isi_violations','isolation_distance','area','probe_id',...
    'spike_times','spike_times_index'}, ...
    'description', 'Units table', ...
    'id', types.hdmf_common.ElementIdentifiers( ...
    'data', int64(0:length(spikes) - 1)), ...
    'cluster_id', types.hdmf_common.VectorData( ...
    'data', metadata(:,1), ...
    'description', 'Unique cluster id'), ...
    'local_cluster_id', types.hdmf_common.VectorData( ...
    'data', metadata(:,2), ...
    'description', 'Local cluster id on the probe'), ...
    'type', types.hdmf_common.VectorData( ...
    'data', metadata(:,3), ...
    'description', 'Cluster type: unit vs mua'), ...
    'peak_channel_index', types.hdmf_common.VectorData( ...
    'data', metadata(:,4), ...
    'description', 'Peak channel row index in the electrode table'), ...
    'peak_channel_id', types.hdmf_common.VectorData( ...
    'data', metadata(:,5), ...
    'description', 'Unique ID of the channel with the largest cluster waveform amplitude'), ...
    'local_peak_channel_id', types.hdmf_common.VectorData( ...
    'data', metadata(:,6), ...
    'description', 'Local probe channel with the largest cluster waveform amplitude'), ...
    'rel_horz_pos', types.hdmf_common.VectorData( ...
    'data', num2cell(cell2mat(table2array(metadata(:,7)))./1000), ...
    'description', 'Probe-relative horizontal position in mm'), ...
    'rel_vert_pos', types.hdmf_common.VectorData( ...
    'data', num2cell(cell2mat(table2array(metadata(:,8)))./1000), ...
    'description', 'Probe tip-relative vertical position in mm'), ...
    'isi_violations', types.hdmf_common.VectorData( ...
    'data', metadata(:,9), ...
    'description', 'Interstimulus interval violations (unit quality measure)'), ...
    'isolation_distance', types.hdmf_common.VectorData( ...
    'data', metadata(:,10), ...
    'description', 'Cluster isolation distance (unit quality measure)'), ...
    'area', types.hdmf_common.VectorData( ...
    'data', metadata(:,11), ...
    'description', ['Brain area where the unit is located. Internal thalamic' ...
    'nuclei divisions are not precise, because they are derived from unit locations on the probe.']), ...
    'probe_id', types.hdmf_common.VectorData( ...
    'data', metadata(:,12), ...
    'description', 'Probe id where the unit is located'), ...
    'spike_times', spike_times_vector, ...
    'spike_times_index', spike_times_index, ...
    'electrode_group', types.hdmf_common.VectorData( ...
    'data', metadata(:,13), ...
    'description', 'Recording channel groups'), ...
    'electrodes', types.hdmf_common.DynamicTableRegion('table', ...
    types.untyped.ObjectView('/general/extracellular_ephys/electrodes'), ...
    'description',  'Probe recording channels', ...
    'data', cell2mat(table2array(metadata(:,1)))), ...
    'waveform_mean', types.hdmf_common.VectorData( ...
    'data', waveformMeans, ...
    'description', ['Mean waveforms on the probe channel with the largest waveform amplitude.' ...
    'MUA waveforms are excluded. The order that waveforms are stored match the order of units in the unit table.']) ...
    );
  
  % Add behavioural data: Pupil area size
  % see https://neurodatawithoutborders.github.io/matnwb/doc/+types/+core/TimeSeries.html
  % and https://neurodatawithoutborders.github.io/matnwb/doc/+types/+core/PupilTracking.html
  acceptablePeriod = derivedData.dataStruct.eyeData.([animalID '_s' sessionID{iSess}]).period; % Acceptable quality range in seconds
  videoFrameTimes = derivedData.dataStruct.eyeData.([animalID '_s' sessionID{iSess}]).frameTimes; % seconds
  acceptableSamples = markQualitySamples(acceptablePeriod, videoFrameTimes);
  pupilAreaSize = derivedData.dataStruct.eyeData.([animalID '_s' sessionID{iSess}]).pupilArea; % pixels^2
  pupilAreaSize = types.core.TimeSeries( ...
    'data', pupilAreaSize, ...
    'timestamps', videoFrameTimes, ...
    'data_unit', 'pixels^2', ...
    'starting_time_rate', videoFrameRate,...
    'control', uint8(acceptableSamples),...
    'control_description', {'low quality samples that should be excluded from analyses';...
    'acceptable quality samples'},...
    'description', ['Pupil area size over the recording session measured in pixels^2' ...
    'Acceptable quality period starting and ending times are given by data_continuity parameter.' ...
    'The full data range can be divided into multiple acceptable periods'] ...
    );
  
  pupilTracking = types.core.PupilTracking('TimeSeries', pupilAreaSize);
  behaviorModule = types.core.ProcessingModule('description', 'contains behavioral data');
  behaviorModule.nwbdatainterface.set('PupilTracking', pupilTracking);
  
  % Add behavioural data: Total movement of the facial area
  % see https://neurodatawithoutborders.github.io/matnwb/doc/+types/+core/TimeSeries.html
  % and https://neurodatawithoutborders.github.io/matnwb/doc/+types/+core/BehavioralTimeSeries.html
  acceptablePeriod = derivedData.dataStruct.motionData.([animalID '_s' sessionID{iSess}]).period; % Acceptable quality range in seconds
  videoFrameTimes = derivedData.dataStruct.motionData.([animalID '_s' sessionID{iSess}]).frameTimes; % seconds
  acceptableSamples = markQualitySamples(acceptablePeriod, videoFrameTimes);
  totalFaceMovement = derivedData.dataStruct.motionData.([animalID '_s' sessionID{iSess}]).sa; % z-scored change in the frame pixels' content with respect to the previous frame
  totalFaceMovement = types.core.TimeSeries( ...
    'data', totalFaceMovement, ...
    'timestamps', videoFrameTimes, ...
    'data_unit', 'a.u.', ...
    'control', uint8(acceptableSamples),...
    'control_description', {'low quality samples that should be excluded from analyses';...
    'acceptable quality samples'},...
    'description', ['Z-scored change in the frame pixels'' content with respect to the previous frame.' ...
    'It measures the total movement of objects inside the video.'] ...
    );
  
  behavioralTimeSeries = types.core.BehavioralTimeSeries('TimeSeries', totalFaceMovement);
  behaviorModule.nwbdatainterface.set('BehavioralTimeSeries', behavioralTimeSeries);
  nwb.processing.set('behavior', behaviorModule);
  
  % Save the NWB file for the session
  if iSess < 10
    nwbExport(nwb, [animalDerivedDataFolderNWB filesep 'ecephys_session_0' num2str(iSess) '.nwb']);
  else
    nwbExport(nwb, [animalDerivedDataFolderNWB filesep 'ecephys_session_' num2str(iSess) '.nwb']);
  end
end

% Read the NWB file
%nwb2 = nwbRead('ecephys_test.nwb');



%% Local functions
function tbl = createElectrodeTable(nwb, input)
% tbl = createElectrodeTable(nwb, input)
%
% Function creates an electrode table with the following columns:
%   channel_id: a unnique probe channel ID formed by combining session ID,
%               probe reference number, and channel number relative to the
%               tip of the probe.
%   channel_local_index: channel index relative to the tip of the probe.
%                        Channel indices are only unique within a probe.
%   x: channel AP brain surface coordinate (probe inisertion location; mm).
%   y: channel ML brain surface coordinate (probe inisertion location; mm).
%   z: channel location relative to the tip of the probe in mm.
%   imp: channel impedance.
%   location: channel brain area location.
%   filtering: type of LFP filtering applied.
%   group: channel electrode group (e.g., shank 1). NWB documentation on
%          ElectrodeGroup datatype is provided in the following links:
%          https://nwb-schema.readthedocs.io/en/latest/format.html#electrodegroup
%          https://nwb-schema.readthedocs.io/en/latest/format.html#sec-electrodegroup-src
%   channel_label
%   probe_label.
% The rows of the table correspond to individual recording channels.
%
%   Input: nwb - nwb object.
%          input - structure with the following fields:
%            iElectrode: electrode reference number.
%            electrodeDescription: a cell array (n probes) with probe
%                                  desciptions.
%            electrodeManufacturer: a cell array of electrode manufacturers.
%            nShanks: a cell array of number of shanks.
%            nChannelsPerShank: a cell array of electrode number of
%                               recording channels per shank.
%            electrodeLocation: a cell array (n channels) of channel brain
%                               area locations.
%            electrodeCoordinates: a cell array (n probes) with recording
%                                  channel coordinate arrays (n channels by
%                                  3).
%            sessionID: a string with the session ID.
%            electrodeLabel: a cell array (n probes) with probe labels.
%
%   Output: tbl - a Matlab table object with rows and columns as described
%                 above.

% Parse input
iEl = input.iElectrode;
nSh = input.nShanks;
nCh = input.nChannelsPerShank;

% Create an table with given column labels
variables = {'channel_id', 'channel_local_index', 'x', 'y', 'z', 'imp', 'location', 'filtering', 'group', 'channel_label', 'probe_label'};
tbl = cell2table(cell(0, length(variables)), 'VariableNames', variables);

% Register the probe device
device = types.core.Device(...
  'description', input.electrodeDescription{iEl}, ...
  'manufacturer', input.electrodeManufacturer{iEl} ...
  );
nwb.general_devices.set(['probe' num2str(iEl)], device);

for iShank = 1:nSh{iEl}
  
  % Register a shank electrode group (only one because this is a single shank probe)
  electrode_group = types.core.ElectrodeGroup( ...
    'description', ['electrode group for probe' num2str(iEl)], ...
    'location', input.electrodeLocation{iEl}{end}, ...
    'device', types.untyped.SoftLink(device), ...
    'position', table(input.electrodeCoordinates{iEl}(1,1), ...
    input.electrodeCoordinates{iEl}(1,2), ...
    input.electrodeCoordinates{iEl}(1,3), ...
    'VariableNames',{'x','y','z'}) ...
    );
  nwb.general_extracellular_ephys.set(['probe' num2str(iEl)], electrode_group);
  group_object_view = types.untyped.ObjectView(electrode_group);
  
  % Populate the electrode table
  for iCh = 1:nCh{iEl}
    if iCh < 10
      channelID = str2double([input.sessionID num2str(iEl) '00' num2str(iCh)]);
    elseif iCh < 99
      channelID = str2double([input.sessionID num2str(iEl) '0' num2str(iCh)]);
    else
      channelID = str2double([input.sessionID num2str(iEl) num2str(iCh)]);
    end
    channel_label = ['probe' num2str(iEl) 'shank' num2str(iShank) 'elec' num2str(iCh)];
    tbl = [tbl; ...
      {channelID, iCh, input.electrodeCoordinates{iEl}(iCh, 1), input.electrodeCoordinates{iEl}(iCh, 2), input.electrodeCoordinates{iEl}(iCh, 3),...
      NaN, input.electrodeLocation{iEl}{iCh}, 'unknown', group_object_view, channel_label, input.electrodeLabel{iEl}}]; %#ok<*AGROW>
  end
end
end

function [spikes, metadataTbl, derivedData] = getNeuronexusSpikes(animalDerivedDataFile, animalID, sessionID, electrodeTbl)
% getNeuronexusSpikes(animalDerivedDataFile, animalID, sessionID, electrodeTbl)
%
% Function loads Neuronexus spiking data from a MAT file with a custom data
% structure. Input:
%   animalDerivedDataFile - a string with derived data file name.
%   animalID - an animal ID string.
%   sessionID - a session of interest ID string.
%   electrodeTbl - a Matlab table with electrode information generated by
%                  the function createElectrodeTable.
% Output: spikes - a 1-by-n cell array (n units) with unit spike times in
%                  seconds.
%         metadataTbl - a Matlab table with rows corresponding to
%                       individual clusters (units) and columns to:
%           cluster_id: a unique cluster ID formed by combining session
%                       ID, probe reference number, and unit cluster ID.
%           local_cluster_id: a unit cluster ID. This is only unique
%                             within the probe.
%           type - activity type: single unit (unit) or multi-unit (mua).
%           channel_index: recording channel with the highest unit peak
%                          index relative to the tip of the probe.
%           channel_id: a corresponding unnique probe channel ID formed by
%                       combining session ID, probe reference number, and
%                       channel number relative to the tip of the probe.
%           local_channel_id: a corresponding channel index relative to the
%                             tip of the probe. Channel indices are only
%                             unique within a probe.
%           rel_horz_position: relative horizontal position in um.
%           rel_vert_position: probe tip-relative vertical position in um.
%           isi_violations: interspike interval violations, a cluster
%                           quality measure.
%           isolation_distance: cluster isolation distance, a cluster
%                           quality measure.
%           area: unit brain area location.
%           probe_id: probe label.
%           electrode_group: channel electrode group (e.g., shank 1). NWB
%                            documentation on ElectrodeGroup datatype is
%                            provided in the following links:
%                            https://nwb-schema.readthedocs.io/en/latest/format.html#electrodegroup
%                            https://nwb-schema.readthedocs.io/en/latest/format.html#sec-electrodegroup-src
%         derivedData - animal data loaded from the MAT derived data file.

% Data series names with different brain areas
derivedData = load(animalDerivedDataFile);
dataSeriesNameS1 = [animalID '_s' sessionID '1'];
dataSeriesNameVB = [animalID '_s' sessionID '2'];
dataSeriesNamePo = [animalID '_s' sessionID '3'];
dataSeriesNameLP = [animalID '_s' sessionID '4'];
dataSeriesNameDG = [animalID '_s' sessionID '5'];
dataSeriesNameCA1 = [animalID '_s' sessionID '6'];
dataSeriesNameRSC = [animalID '_s' sessionID '7'];

% Series data
seriesDerivedDataS1 = derivedData.dataStruct.seriesData.(dataSeriesNameS1);
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameVB)
  seriesDerivedDataVB = derivedData.dataStruct.seriesData.(dataSeriesNameVB);
end
seriesDerivedDataPo = derivedData.dataStruct.seriesData.(dataSeriesNamePo);
seriesDerivedDataLP = derivedData.dataStruct.seriesData.(dataSeriesNameLP);
seriesDerivedDataDG = derivedData.dataStruct.seriesData.(dataSeriesNameDG);
seriesDerivedDataCA1 = derivedData.dataStruct.seriesData.(dataSeriesNameCA1);
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameRSC)
  seriesDerivedDataRSC = derivedData.dataStruct.seriesData.(dataSeriesNameRSC);
end

% Series unit data
seriesDerivedUnitDataS1 = seriesDerivedDataS1.shankData.shank1;
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameVB)
  seriesDerivedUnitDataVB = seriesDerivedDataVB.shankData.shank1;
end
seriesDerivedUnitDataPo = seriesDerivedDataPo.shankData.shank1;
seriesDerivedUnitDataLP = seriesDerivedDataLP.shankData.shank1;
seriesDerivedUnitDataDG = seriesDerivedDataDG.shankData.shank1;
seriesDerivedUnitDataCA1 = seriesDerivedDataCA1.shankData.shank1;
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameRSC)
  seriesDerivedUnitDataRSC = seriesDerivedDataRSC.shankData.shank1;
end

% Series population data
seriesDerivedPopulationDataS1 = seriesDerivedDataS1.popData;
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameVB)
  seriesDerivedPopulationDataVB = seriesDerivedDataVB.popData;
end
seriesDerivedPopulationDataPo = seriesDerivedDataPo.popData;
seriesDerivedPopulationDataLP = seriesDerivedDataLP.popData;
seriesDerivedPopulationDataDG = seriesDerivedDataDG.popData;
seriesDerivedPopulationDataCA1 = seriesDerivedDataCA1.popData;
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameRSC)
  seriesDerivedPopulationDataRSC = seriesDerivedDataRSC.popData;
end

% Spike array
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameVB)
  sparseSpikes = concatenateMat(seriesDerivedPopulationDataS1.spkDB, seriesDerivedPopulationDataVB.spkDB);
  sparseSpikes = concatenateMat(sparseSpikes, seriesDerivedPopulationDataPo.spkDB);
else
  sparseSpikes = concatenateMat(seriesDerivedPopulationDataS1.spkDB, seriesDerivedPopulationDataPo.spkDB);
end
sparseSpikes = concatenateMat(sparseSpikes, seriesDerivedPopulationDataLP.spkDB);
sparseSpikes = concatenateMat(sparseSpikes, seriesDerivedPopulationDataDG.spkDB);
sparseSpikes = concatenateMat(sparseSpikes, seriesDerivedPopulationDataCA1.spkDB);
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameRSC)
  sparseSpikes = concatenateMat(sparseSpikes, seriesDerivedPopulationDataRSC.spkDB);
end

% Spike times
nRows = size(sparseSpikes,1);
timeVector = (1:size(sparseSpikes,2))./seriesDerivedDataS1.conf.samplingParams.srData;
for iUnit = 1:nRows
  spikes{iUnit} = timeVector(logical(full(sparseSpikes(iUnit,:)))); %#ok<*SAGROW>
end

% Unit metadata: [local_unit_id type local_probe_channel horizontal_position vertical_position ...
%                 isi_violations isolation_distance anterior_posterior_ccf_coordinate ...
%                 dorsal_ventral_ccf_coordinate left_right_ccf_coordinate]
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameVB)
  metadata = concatenateMat(seriesDerivedPopulationDataS1.muaMetadata, seriesDerivedPopulationDataVB.muaMetadata);
  metadata = concatenateMat(metadata, seriesDerivedPopulationDataPo.muaMetadata);
else
  metadata = concatenateMat(seriesDerivedPopulationDataS1.muaMetadata, seriesDerivedPopulationDataPo.muaMetadata);
end
metadata = concatenateMat(metadata, seriesDerivedPopulationDataLP.muaMetadata);
metadata = concatenateMat(metadata, seriesDerivedPopulationDataDG.muaMetadata);
metadata = concatenateMat(metadata, seriesDerivedPopulationDataCA1.muaMetadata);
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameRSC)
  metadata = concatenateMat(metadata, seriesDerivedPopulationDataRSC.muaMetadata);
end

% Unit metadata: [area metadata]
areas = repmat({'S1'}, size(seriesDerivedPopulationDataS1.muaMetadata,1), 1);
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameVB)
  areas = [areas; repmat({'VB'}, size(seriesDerivedPopulationDataVB.muaMetadata,1), 1)];
end
areas = [areas; repmat({'Po'}, size(seriesDerivedPopulationDataPo.muaMetadata,1), 1)];
areas = [areas; repmat({'LP'}, size(seriesDerivedPopulationDataLP.muaMetadata,1), 1)];
areas = [areas; repmat({'DG'}, size(seriesDerivedPopulationDataDG.muaMetadata,1), 1)];
areas = [areas; repmat({'CA1'}, size(seriesDerivedPopulationDataCA1.muaMetadata,1), 1)];
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameRSC)
  areas = [areas; repmat({'RSC'}, size(seriesDerivedPopulationDataRSC.muaMetadata,1), 1)];
end
metadata = [num2cell(metadata) areas];

% Unit metadata: correct unit type
units = ismember(seriesDerivedPopulationDataS1.spkDB_units, seriesDerivedUnitDataS1.units);
typeS1 = repmat({'mua'}, size(seriesDerivedPopulationDataS1.muaMetadata,1), 1); typeS1(units) = {'unit'};
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameVB)
  units = ismember(seriesDerivedPopulationDataVB.spkDB_units, seriesDerivedUnitDataVB.units);
  typeVB = repmat({'mua'}, size(seriesDerivedPopulationDataVB.muaMetadata,1), 1); typeVB(units) = {'unit'};
end
units = ismember(seriesDerivedPopulationDataPo.spkDB_units, seriesDerivedUnitDataPo.units);
typePo = repmat({'mua'}, size(seriesDerivedPopulationDataPo.muaMetadata,1), 1); typePo(units) = {'unit'};
units = ismember(seriesDerivedPopulationDataLP.spkDB_units, seriesDerivedUnitDataLP.units);
typeLP = repmat({'mua'}, size(seriesDerivedPopulationDataLP.muaMetadata,1), 1); typeLP(units) = {'unit'};
units = ismember(seriesDerivedPopulationDataDG.spkDB_units, seriesDerivedUnitDataDG.units);
typeDG = repmat({'mua'}, size(seriesDerivedPopulationDataDG.muaMetadata,1), 1); typeDG(units) = {'unit'};
units = ismember(seriesDerivedPopulationDataCA1.spkDB_units, seriesDerivedUnitDataCA1.units);
typeCA1 = repmat({'mua'}, size(seriesDerivedPopulationDataCA1.muaMetadata,1), 1); typeCA1(units) = {'unit'};
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameRSC)
  units = ismember(seriesDerivedPopulationDataRSC.spkDB_units, seriesDerivedUnitDataRSC.units);
  typeRSC = repmat({'mua'}, size(seriesDerivedPopulationDataRSC.muaMetadata,1), 1); typeRSC(units) = {'unit'};
end
if isfield(derivedData.dataStruct.seriesData, dataSeriesNameVB) && isfield(derivedData.dataStruct.seriesData, dataSeriesNameRSC)
  type = [typeS1; typeVB; typePo; typeLP; typeDG; typeCA1; typeRSC];
else
  if isfield(derivedData.dataStruct.seriesData, dataSeriesNameVB)
    type = [typeS1; typeVB; typePo; typeLP; typeDG; typeCA1];
  else
    type = [typeS1; typePo; typeLP; typeDG; typeCA1; typeRSC];
  end
end
metadata(:,2) = type;

% Unit metadata: [metadata probe_id]
metadata = [metadata [repmat({'probe1'},numel(typeS1),1); repmat({'probe2'},numel(type)-numel(typeS1),1)]];

% Unit metadata: [unit_id metadata]
unitIDs = zeros(nRows,1);
for iUnit = 1:nRows
  if strcmpi(metadata{iUnit, end}, 'probe1')
    unitID = [num2str(sessionID) '1'];
  else
    unitID = [num2str(sessionID) '2'];
  end
  if metadata{iUnit, 1} < 9
    unitID = [unitID '000' num2str(metadata{iUnit, 1})];
  elseif metadata{iUnit, 1} < 99
    unitID = [unitID '00' num2str(metadata{iUnit, 1})];
  elseif metadata{iUnit, 1} < 999
    unitID = [unitID '0' num2str(metadata{iUnit, 1})];
  else
    unitID = [unitID num2str(metadata{iUnit, 1})];
  end
  unitIDs(iUnit) = str2double(unitID);
end
metadata = [num2cell(unitIDs) metadata];

% Unit metadata: [metadata(:,1:3) probe_channel_index probe_channel_id metadata(:,4:end)]
channelIndices = zeros(nRows,1);
channelIDs = zeros(nRows,1);
electrodeGroups = {};
for iUnit = 1:nRows
  ind = table2array(electrodeTbl(:,2)) == cell2mat(metadata(iUnit,4)) &...
    contains(table2array(electrodeTbl(:,end)), metadata(iUnit,end));
  channelIndices(iUnit) = find(ind);
  channelIDs(iUnit) = table2array(electrodeTbl(ind,1));
  electrodeGroups = [electrodeGroups; table2array(electrodeTbl(ind,9))];
end
metadata = [metadata(:,1:3) num2cell(channelIndices) num2cell(channelIDs) metadata(:,4:end)];

% Unit metadata: [metadata electrode_group]
metadataTbl = table(metadata(:,1), metadata(:,2), metadata(:,3), metadata(:,4), ...
  metadata(:,5), metadata(:,6), metadata(:,7), metadata(:,8), ...
  metadata(:,9), metadata(:,10), metadata(:,11), metadata(:,12), electrodeGroups, ...
  'VariableNames', {'cluster_id', 'local_cluster_id', 'type',...
  'channel_index', 'channel_id', 'local_channel_id',...
  'rel_horz_pos','rel_vert_pos', 'isi_violations',...
  'isolation_distance', 'area', 'probe_id', 'electrode_group'});
end

function [reshapedWaveformsMat, reshapedWaveformsVecGrp, reshapedWaveformsVec, waveformsMean] = reshapeWaveforms(waveforms, iEl, metadata)
% [reshapedWaveformsMat, reshapedWaveformsVecGrp, reshapedWaveformsVec, waveformsMean] = reshapeWaveforms(waveforms, iEl, metadata)
%
% Function extracts relevant waveform information and reshapes the waveform
% array which is 3-dimensional with the first dimension being the unit, the
% second being the sample point, and the third one being the recording
% channel.
% Input: waveforms - a strucuture loaded from the waveforms MAT file.
%                    Relevant fields are waveforms (described above),
%                    maxWaveforms (same as waveforms but excluding all
%                    channels except for the maximum amplitude one), and
%                    cluIDs (unit cluster IDs corresponding to the
%                    dimension one in waveforms and maxWaveforms).
%        iEl - probe reference number.
%        metadata - a Matlab unit table produced by the function
%                   getNeuronexusSpikes.
% Output: reshapedWaveformsMat - a 2D array reshaping waveforms.waveforms
%                                array by collapsing the third dimension
%                                and stacking all waveforms vertically one
%                                unit after another.
%         reshapedWaveformsVecGrp - a column cell array reshaping
%                                   waveforms.waveforms array and grouping
%                                   all waveforms from the same unit
%                                   together. Cell array entries correspond
%                                   to individual units. The missing MUAs
%                                   correspond to empty cell arrays.
%         reshapedWaveformsVec - a cell array with rows from
%                                reshapedWaveformsMat. Missing MUAs are
%                                also included as empty cells times the
%                                number of recording channels.
%         waveformsMean - waveforms.waveforms converted into a cell column
%                         array. MUAs are NaNs.

reshapedWaveformsMat = zeros(size(waveforms.waveforms,1)*size(waveforms.waveforms,3),size(waveforms.waveforms,2));
reshapedWaveformsVecGrp = {};
reshapedWaveformsVec = {};
waveformsMean = {};
metadataInds = ismember(table2cell(metadata(:,12)), ['probe' num2str(iEl)]);
metadata = metadata(metadataInds,:);
for iUnit = 1:size(metadata,1)
  row = find(ismember(waveforms.cluIDs, cell2mat(table2cell(metadata(iUnit,2)))));
  if sum(ismember(waveforms.cluIDs, cell2mat(table2cell(metadata(iUnit,2)))))
    unitWaveformMat = squeeze(waveforms.waveforms(row,:,:))';
    reshapedWaveformsMat((row-1)*size(waveforms.waveforms,3)+1:row*size(waveforms.waveforms,3),:) = unitWaveformMat;
    reshapedWaveformsVecGrp = [reshapedWaveformsVecGrp; {unitWaveformMat}];
    for iWave = 1:size(unitWaveformMat,1)
      reshapedWaveformsVec = [reshapedWaveformsVec; {unitWaveformMat(iWave,:)}];
    end
    waveformsMean = [waveformsMean; {waveforms.maxWaveforms(row,:)}];
  else
    reshapedWaveformsVecGrp = [reshapedWaveformsVecGrp; {[]}];
    for iWave = 1:size(waveforms.waveforms,3)
      reshapedWaveformsVec = [reshapedWaveformsVec; {[]}];
    end
    waveformsMean = [waveformsMean; {nan(1,size(waveforms.maxWaveforms,2))}];
  end
end
end

function acceptableSamples = markQualitySamples(acceptablePeriod, videoFrameTimes)
% acceptableSamples = markQualitySamples(acceptablePeriod, videoFrameTimes)
%
% Function marks acceptable behavioural samples given the sample times and
% the range of acceptable time periods.
% Input: acceptablePeriod - a vector or a cell array of vectors marking the
%                           beginning and end of acceptable time periods.
%        videoFrameTimes - a vector with sample times.
% Ouptut: acceptableSamples - a logical vector marking acceptable samples
%                             by ones.

if isempty(acceptablePeriod) || isempty(videoFrameTimes)
  acceptableSamples = [];
else
  acceptableSamples = false(size(videoFrameTimes));
  if iscell(acceptablePeriod)
    for iPeriod = 1:numel(acceptablePeriod)
      acceptableSamples(videoFrameTimes >= acceptablePeriod{iPeriod}(1) & videoFrameTimes <= acceptablePeriod{iPeriod}(2)) = true;
    end
  else
    acceptableSamples(videoFrameTimes >= acceptablePeriod(1) & videoFrameTimes <= acceptablePeriod(2)) = true;
  end
end
end