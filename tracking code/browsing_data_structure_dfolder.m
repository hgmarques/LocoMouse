function [] = browsing_data_structure_dfolder(session_path,output_path,model_path,dist_image_path,distortion_path,error_path,skip_analyzed_videos,skip_undistortion)
%% Processing data:
t_overall_start = tic;
fprintf('Looking for model under %s ...',model_path);
try
    load(model_path,'model');
    fprintf(' Found!\n');
catch
    fprintf(' Failed!\n');
    return;
end

fprintf('Looking for calibration file under %s ...',dist_image_path);
try
    load(distortion_path,'IDX','mirror_line');
    fprintf(' Found!\n');
catch
    fprintf(' Failed!\n');
    return;
end

fprintf('Separating side from bottom view at %d pixels.\n',mirror_line);
data.mirror_line = mirror_line;
exclude_navigation_dir = {'.','..','GREY','calibration'}; % folders to ignore

fprintf('Looking for videos under: %s\n',session_path);
session_list = dir(session_path);

% Make sure only browsing folders...
session_list = session_list(cell2mat({session_list(:).isdir}));
N_sessions = length(session_list);

current_path = pwd;
cd(session_path)

% Loading model and distortion parameters:

% Creating output path:
if ~exist(output_path,'dir')
    mkdir(output_path);
end

sessions_exist = false;

for i_s = 1:N_sessions
    % Navigate the session:
    if any(strcmp(session_list(i_s).name,exclude_navigation_dir))
        continue;
    end
    sessions_exist = true;
        
    % Go to session directory
    fprintf('Current session: %s\n',session_list(i_s).name);
    cd(session_list(i_s).name);
    find_S = session_list(i_s).name == 'S';
    session_counter = str2double(session_list(i_s).name(find_S+1:end));
    
    % Navigate the animals:
    animal_list = dir(pwd);
    animal_list = animal_list(cell2mat({animal_list(:).isdir}));
    N_animals = length(animal_list);
    animals_exist = false;
    
    for i_a = 1:N_animals
        if any(strcmp(animal_list(i_a).name,exclude_navigation_dir))
            continue;
        end
        animals_exist = true;
        
        fprintf('Current animal: %s\n',animal_list(i_a).name);
        cd(animal_list(i_a).name);
        
        bg_name = dir([pwd filesep '*.png']);
        if isempty(bg_name)
            warning('There is no background image in %s. Computing background using median.',animal_list(i_a).name);
            Ibg = 'median';
        else
            if length(bg_name) > 1
                warning('There is more than one image in %s. Using the first one...',animal_list(i_a).name);
            end
            Ibg = imread(bg_name(1).name);
        end
        
        % Go to animal directory:
        video_list = dir('*.avi');
        N_videos = length(video_list);
        fprintf('%d video(s) found for current animal.\n',N_videos);
        
        %% processing movie
        for i_v = 1:N_videos
            try % error display
                % Saving images at the right location:
                cd(output_path);
                
                if ~exist(fullfile(pwd,animal_list(i_a).name),'dir')
                    mkdir(animal_list(i_a).name);
                end
                cd(animal_list(i_a).name);
                
                if ~exist(fullfile(pwd,session_list(i_s).name),'dir')
                    mkdir(session_list(i_s).name)
                end
                cd(session_list(i_s).name)
                
                % Checking if the corrected video already exists:
                [~,name,~] = fileparts(video_list(i_v).name);
                
                % If matfile exists and we are skipping, skip:
                if skip_analyzed_videos && (exist(fullfile(pwd,'data',sprintf('%s_L.mat',name)),'file') || exist(fullfile(pwd,'data',sprintf('%s_R.mat',name)),'file'))
                    continue;
                end
                
                imdir = fullfile(dist_image_path,[name '_corrected']);
                if exist(fullfile(imdir),'dir')
                    data.sequence = getDataList([imdir filesep '*.png']);
                else
                    data.sequence = [];
                end
                had_to_track_again = false;
                
                if  ~skip_undistortion || isempty(data.sequence)
                    had_to_track_again = true;

                    fprintf('Extracting images for %s\n',video_list(i_v).name);
                    % If the video has not been corrected yet, we must generate the
                    % images for correction:
                    t_start_imcorr = tic;
                    try
                        delete(fullfile(imdir,'*.png'))
                    catch
                    end
                    if ~exist(imdir,'dir')
                    mkdir(imdir);
                    end
                    % Extracting frames from video
                    flip = extractFramesVideo(fullfile(session_path,session_list(i_s).name,animal_list(i_a).name,video_list(i_v).name),imdir,[name '_%05d.png'],'Background',Ibg,'Flip',true,'Undistort',{IDX,mirror_line});
                    fprintf(['Done. Elapsed time: ' datestr(toc(t_start_imcorr)/3600/24,'DD:HH:MM:SS') '\n']);
                    clear bkg dot_pos
                  
                else
                    vid  = VideoReader(fullfile(session_path,session_list(i_s).name,animal_list(i_a).name,video_list(i_v).name));
                    flip = checkMouseSide(vid,Ibg);
                    clear vid
                end
                
                % Checking the mouse side:
                if flip
                    departure_side = '_R';
                else
                    departure_side = '_L';
                end
            
                cd(imdir);
                
                data.sequence = getDataList([imdir filesep '*.png']);
                fprintf('Tracking %s\n',video_list(i_v).name);
                t_start_tracking = tic;
                
                %% Tracking code
                [final_tracks,tracks_tail] = MTF_newwindow(data,model);
                fprintf(['Done. Elapsed time: ' datestr(toc(t_start_tracking)/3600/24,'DD:HH:MM:SS') '\n']);
                cd(fullfile(output_path,animal_list(i_a).name,session_list(i_s).name));
                % Print images:
                if~exist(fullfile(pwd,'images'),'dir')
                    mkdir('images')
                end
                if ~exist(fullfile(pwd,'data'),'dir')
                    mkdir('data')
                end
                cd('images')
                % Exporting figures:
                fprintf('Saving figures of tracking output...');
                try
                    MTF_export_figures(final_tracks,tracks_tail,video_list(i_v).name);
                    fprintf(' Done!\n');
                catch
                    fprintf(' Failed!\n');
                end
                cd(fullfile('..','data'))
                fprintf('Saving mat file with output...');
                try
                    save(sprintf(['%s' departure_side '.mat'],name),'final_tracks','tracks_tail','IDX','mirror_line','name');
                    fprintf(' Done!\n');
                catch
                    fprintf(' Failed!\n');
                end
%                 cd(fullfile('..','images'))

            catch % error display
                fprintf('Error while tracking %s. Saving partial results MAT file...',video_list(i_v).name)
                if ~exist(error_path,'dir')
                    mkdir(error_path)
                end
                % Write a file.
                save(fullfile(error_path,sprintf('%s.mat',video_list(i_v).name(1:end-4))));
                fprintf(' Done.\n');                
                
            end% error display
        end
        cd(fullfile(session_path,session_list(i_s).name));
    end
    if ~animals_exist
        fprintf('No animals were found for current session!\n');
    end
    cd(session_path);
end

if ~sessions_exist
    fprintf('No sessions were found!\n');
end
cd(current_path);
