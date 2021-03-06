clear all
close all
clc

%% Create TCP connection
% mask = false(96);
% mask(44:49,44:50) = true;

% Create TCP/IP object 'fncngen'. Specify server machine and port number. 
fncngen = tcpip('10.200.32.101', 5025,'NetworkRole','Client'); 

% Set size of receiving buffer, if needed. 
set(fncngen, 'InputBufferSize', 30000); 

disp('opening connection..')
% Open connection to the server. 
fopen(fncngen);
disp('connection created!');

%% Initialize pulser

ncycles = 500;
freq = 1.1; % MHz
Vmax = 60e-3; % V
Vmin = 5e-3; % V

fprintf(fncngen,'OUTP1 OFF;');
fprintf(fncngen,'OUTP1:LOAD 50.0');
fprintf(fncngen,'OUTP1:POL NORM');

fprintf(fncngen,'SOUR1:FUNC:SHAP SIN;');
%fprintf(t,'SOUR1:FREQ 1.1e+06;');
%fprintf(t,'SOUR1:FREQ 3.68e+06;');
cmd = sprintf('SOUR1:FREQ %1.3fe+06;',freq);
fprintf(fncngen,cmd);
fprintf(fncngen,'SOUR1:VOLT:UNIT VPP;');
fprintf(fncngen,'SOUR1:VOLT 0.005;');
fprintf(fncngen,'SOUR1:VOLT:OFFS 0.0E+00;');
fprintf(fncngen,'SOUR1:VOLT:HIGH 2.5E-03;');
fprintf(fncngen,'SOUR1:VOLT:LOW -2.5E-03;');
%fprintf(t,'SOUR1:PHASe 0.000000E+00;');
fprintf(fncngen,'UNIT:ANGLe DEG;');
fprintf(fncngen,'SOUR1:SWEep:STATe OFF;');
fprintf(fncngen,'SOUR1:SWEep:SPAC LIN;');
fprintf(fncngen,'SOUR1:SWEep:RTIMe 0.0E+00;');
fprintf(fncngen,'SOUR1:SWEep:HTIMe 0.0E+00;');
fprintf(fncngen,'SOUR1:FREQ:STOP 1.0E+03;');
fprintf(fncngen,'SOUR1:FREQ:STAR 1.0E+02;');
fprintf(fncngen,'SOUR1:BURSt:STATe OFF;');
fprintf(fncngen,'SOUR1:BURSt:MODE TRIG;');
%fprintf(t,'SOUR1:BURSt:NCYCles 5.000E+02;');
cmd = sprintf('SOUR1:BURSt:NCYCles %1.3fE+00',ncycles);
fprintf(fncngen,cmd);
fprintf(fncngen,'SOUR1:BURst:GATe:POLarity NORM;');
fprintf(fncngen,'SOUR1:BURSt:PHASe 0.0e+00;');
fprintf(fncngen,'UNIT:ANGLe DEG;');
fprintf(fncngen,'OUTP1 OFF;');
fprintf(fncngen,'OUTP1:LOAD 50.0');
fprintf(fncngen,'OUTP1:POL NORM');
% 
% % define mask of focus
%focusmask = false(128);
%focusmask = false(128);
%focusmask(55:60,69:74) = true;
focusmask = false(512);
minr = 250;
maxr = 275;
minc = 228;
maxc = 266;
focusvect = [minc-1 minr-1 maxc-minc+2 maxr-minr+2];
focusmask(minr:maxr,minc:maxc) = true;

% define pid params
ppi.nom = 6; % deg C, target mean temp in focus
ppi.pgain = 0.001; % proportional gain
ppi.igain = 0.00001; 
ppi.dgain = 0.005;
ppi.cmin = 0;
ppi.cmax = 0.1;
voltage = 0;
 
fp = 1;keepgoing = 1;
tmax = 15; % deg C, for display
tmin = -5; 
TE = 0.00407; % s, for calculating temp
TR = 0.015; % s, for calculating time
min = 0;
imdim = 96;

BoCorrection = 0; %set to 1 if want to perform inhomogeneity correction
chooseROI = 0; %set to 1 if want to draw own ROI for inhomogenetiy corr.
noisecancel = 0; %set to 1 if want to subtract noise

roomtemp = 37; %set to body temp
runCEM = [];
voltVals = [];

fname = '~/vnmrsys/exp2/acqfil/fid';
cbegin = clock;
while keepgoing
    fp = fopen(fname,'r','ieee-be');
    % read header, spit out np,nt,nb to console
    % initialize file seek pointer to the index variable of first block
    % if that variable is nonzero, read the data and display ft
    % then increment seek index, and loop back
    
    if fp ~= -1
        % read overall header
        nblocks   = fread(fp,1,'int32');
        ntraces   = fread(fp,1,'int32');
        dt = ntraces*TR; % seconds, time step of images
        t = 0:dt:(nblocks-1)*dt;
        np        = fread(fp,1,'int32');
        ebytes    = fread(fp,1,'int32');
        tbytes    = fread(fp,1,'int32');
        bbytes    = fread(fp,1,'int32');
        vers_id   = fread(fp,1,'int16');
        status    = fread(fp,1,'int16');
        nbheaders = fread(fp,1,'int32');
        
        s_data    = bitget(status,1);
        s_spec    = bitget(status,2);
        s_32      = bitget(status,3);
        s_float   = bitget(status,4);
        s_complex = bitget(status,5);
        s_hyper   = bitget(status,6);
        
        % store current position
        fpos = ftell(fp);
        
        fclose(fp);
        
        % now loop until we have read all the data
        nblocksread = 0;
        meantemp = [];
        meanCEM = [0];
        cstart = clock;
        while nblocksread < nblocks
            
            fp = fopen(fname,'r','ieee-be');
            fseek(fp,fpos,'bof');
            % read block header, check if index ~= 0
            scale     = fread(fp,1,'int16');
            bstatus   = fread(fp,1,'int16');
            index     = fread(fp,1,'int16');
            mode      = fread(fp,1,'int16');
            ctcount   = fread(fp,1,'int32');
            lpval     = fread(fp,1,'float32');
            rpval     = fread(fp,1,'float32');
            lvl       = fread(fp,1,'float32');
            tlt       = fread(fp,1,'float32');
            if index > 0
                % read the data
                %for ii = 1:ntraces
                    %We have to read data every time in order to increment file pointer
                    if s_float == 1
                        data = fread(fp,np*ntraces,'float32');
                    elseif s_32 == 1
                        data = fread(fp,np*ntraces,'int32');
                    else
                        data = fread(fp,np*ntraces,'int16');
                    end
        
                    % keep data if this block & trace was in output list
                    %RE(:,ii) = data(1:2:np*ntraces);
                    %IM(:,ii) = data(2:2:np*ntraces);
                    RE = data(1:2:np*ntraces);
                    IM = data(2:2:np*ntraces);
                    RE = reshape(RE,[np/2 ntraces]);
                    IM = reshape(IM,[np/2 ntraces]);
                %end %trace loop
                % ft and display data
                foobar = zeros(512,512);
                foobar(256-imdim/2+1:256+imdim/2,256-imdim/2+1:256+imdim/2) = RE + 1i*IM;
                %img(:,:,nblocksread+1) = fftshift(fft2(fftshift(RE+1i*IM)));
                img(:,:,nblocksread+1) = fftshift(fft2(fftshift(foobar)));
                
                %% Adjust for noise
                    if noisecancel == 1
                        fdimg = fftshift(fft2(fftshift(img(:,:,nblocksread+1))));
                        h = fspecial('gaussian',[96 96],48);
                        img(:,:,nblocksread+1) = fftshift(ifft2(fftshift(h.*fdimg)));
                    end
                        
                figure(1);
                subplot(331);imagesc(abs(img(:,:,end)));colorbar;axis image
                 %set(gca, 'XTick', [], 'YTick', [])
                title(['Block Index: ' num2str(nblocksread)]);
                if nblocksread > 1
                    foobar = abs(img(:,:,1));
                    mask = abs(img(:,:,1)) > 0.01*max(foobar(:));
                    tmap = angle(img(:,:,nblocksread+1).*conj(img(:,:,1)));
                    %% Correct for field inhomogenity from heating
                    if BoCorrection == 1
                        if (chooseROI == 1) && (nblocksread == 2)
                            [BW, x, y] = roipoly(img(:,:,nblocksread+1));
                            roi = poly2mask(x,y,96,96);
                        elseif chooseROI == 0
                            roi = false (96);
                            roi(55:65,45:55) = true;
                        end
                            phase = angle(roi.*(img(:,:,nblocksread+1)));
                            avgPhase = mean2(phase(phase~=0));
                            tmap = tmap-abs(avgPhase);
                    end
                    
                    tmap = angle(img(:,:,nblocksread+1).*conj(img(:,:,1)));
                    tmap = tmap/(42.58*4.7*0.01*TE*2*pi); % Celsius
                    subplot(332);hold on;
                    imagesc(tmap.*mask,[tmin tmax]);colorbar;title 'degrees C';axis image;
                    rectangle('Position',focusvect,'LineWidth',2,'EdgeColor','k');
                    
                    % set(gca, 'XTick', [], 'YTick', [])
                    meantemp(end+1) = mean(tmap(focusmask));
                    subplot(333);
                    imagesc(tmap.*focusmask,[tmin tmax]);colorbar;title 'degrees C'
                    % set(gca, 'XTick', [], 'YTick', [])
                    axis image
                    sp312 = subplot(312);hold on
                    plot(t(1:length(meantemp)),meantemp);axis([0 eps+t(length(meantemp)) tmin tmax]);
                    plot(t(1:length(meantemp)),ppi.nom*ones(length(meantemp),1),'--r');grid on
                    xlabel 'Time (s) ',ylabel '\delta ^{\circ} C'
                    title(['Block Index: ' num2str(nblocksread) '. Time: ' num2str(t(nblocksread+1)) ' seconds.']);
                    hold off;
                    
                    
%                     % if data exists do CEM Calucaltion 
%                     temps = tmap + roomtemp;                        
%                     dim = size(temps);
%                     if nblocksread == 2
%                         runCEM = zeros(dim(1), dim(2),1);
%                     end
%                     curCEM = zeros(dim(1), dim(2), 3);
%                     R = [0.5 0.25 1];
% 
%                     CEMup = temps > 43 ;
%                     CEMmid = temps == 43;
%                     CEMdown = temps < 43;
%                     curCEM(:,:,1) = (R(1).^(43-(temps.*CEMup)))*TR;
%                     curCEM(:,:,2) = (R(3).^(43-(temps.*CEMmid)))*TR;
%                     curCEM(:,:,3) = (R(2).^(43-(temps.*CEMdown)))*TR;
%                         
%                     curCEM = cumsum(curCEM,3);
%                     runCEM= cat(3,runCEM,curCEM(:,:,3));
%                     sumCEM = cumsum(runCEM,3);
%                     tCEM = sumCEM(:,:,end);
%                     figure(2)
%                     subplot(221);
%                     imagesc(tCEM);
%                     colorbar;
%                     title ('CEM');
%                     axis image;
%                     
%                     roiCEM = tCEM.*mask;
%                     subplot(222);
%                     imagesc(roiCEM);
%                     colorbar;
%                     title ('CEM ROI');
%                     axis image;
%                     
%                     meanCEM(end+1) = mean2(roiCEM(roiCEM~=0));
%                     subplot(212);
%                     plot(t(1:length(meanCEM)),meanCEM);
%                     xlim([0 eps+t(length(meanCEM))]);% tmin tmax]);
%                     xlabel('Block Index');
%                     ylabel ('Mean Dosage (CEM43)');
                    
                    % update the control
                    foobar = tmap(focusmask);
                    %foobar = foobar(foobar >= 0);
                    [voltage,ppi] = piupdateMegan(voltage,mean2(foobar),ppi);
                    if voltage > Vmax
                        voltage = Vmax;
                    end
                    voltVals(end+1) = voltage*1000;
                    subplot(313);hold on;
                    plot(t(1:length(voltVals)),voltVals); grid on;xlabel('Time (s)');
                    plot(t(1:length(voltVals)),Vmax*1000*ones(length(voltVals),1),'--r');grid on
                    hold off;%title(['CEM = ',num2str(meanCEM(end))]);
                    ylabel('Driving voltage (mV)'); 
                    axis([0 eps+t(length(voltVals)) Vmin*1000 Vmax*1000+5])
                    
%                     figure(2);
%                     subplot(212);hold on
%                     [ax, p1, p2] = plotyy(t(1:length(meantemp)),meantemp,t(1:length(voltVals)),voltVals);
%                     xlabel('Time (s)');ylabel(ax(1),'\Delta ^{\circ} C');
%                     ylabel(ax(2),'Voltage (mV)');
% %                     axis([0 eps+t(length(meantemp)) tmin tmax Vmin Vmax]);
%                     axis 'auto yx';
% %                     plot(t(1:length(meantemp)),ppi.nom*ones(length(meantemp),1),'r');grid on
% %                     xlabel 'Block Index',ylabel '\Delta ^{\circ} C'
%                     hold off;
%                     plot(t(1:length(voltVals)),voltVals);

                    % send resulting command to function generator
                    disp(['Changing voltage to: ' num2str(voltage)]);
                    if voltage == 0
                        fprintf(fncngen,'OUTP1 OFF;');
                    else
                        fprintf(fncngen,'OUTP1 ON;');
                        cur_cmd = sprintf('SOUR1:VOLT %1.5f;',voltage);
                        fprintf(fncngen,cur_cmd);
                    end
%                     
                end
                drawnow
%                 set( get(sp312,'title'), 'String', ['Block Index: ' num2str(nblocksread) '. Time: ' num2str(t(nblocksread+1)) ' seconds.']);
%                 title(['Block Index: ' num2str(nblocksread) '. Time: ' num2str(t(nblocksread+1)) ' seconds.']);
                % increment fpos and nblocksread
                fpos = ftell(fp);
                nblocksread = nblocksread + 1;
            end
            fclose(fp);
            c(nblocksread+1,:) = clock;
        end
        
        keepgoing = 0; % we should be all done now
    else
        disp('File not opened yet');
    end
    
    
end
cend = clock;
%% Stop pulsing and close out TCP connection

fprintf(fncngen,'OUTP1 OFF;');

% Disconnect and clean up the server connection. 
fclose(fncngen); 
delete(fncngen); 
clear fncngen

time = c(:,5)+(c(:,6)/60);
computeTime = diff(time);