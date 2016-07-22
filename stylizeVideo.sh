set -e
# Get a carriage return into `cr`
cr=`echo $'\n.'`
cr=${cr%.}


# Find out whether ffmpeg or avconv is installed on the system
FFMPEG=ffmpeg
command -v $FFMPEG >/dev/null 2>&1 || {
  FFMPEG=avconv
  command -v $FFMPEG >/dev/null 2>&1 || {
    echo >&2 "This script requires either ffmpeg or avconv installed.  Aborting."; exit 1;
  }
}

if [ "$#" -le 1 ]; then
   echo "Usage: ./stylizeVideo <path_to_video> <path_to_style_image>"
   exit 1
fi

# Parse arguments
DATE=$(date -d "today" +"%Y%m%d%H%M")
style_video=${1##*/}
style_video_base=${style_video%.*}
style_image=${2##*/}
style_image_base=${style_image%.*}
filename=${style_video_base}_${2##*/}
extension="${style_video##*.}"
filename="${filename%.*}"
filename=${filename//[%]/x}

mkdir -p /content/output/$filename-$DATE
mkdir -p /content/vid/$style_video_base/frames/
mkdir -p /content/vid/$style_video_base/flow/

touch /content/output/$filename-$DATE/$filename-$DATE.log.txt
logfile=/content/output/$filename-$DATE/$filename-$DATE.log.txt

echo "date is $(date "+%Y-%m-%d %H:%M:%S") " | tee -a $logfile
echo "filename is" $filename | tee -a $logfile
echo "style_video is " $style_video  | tee -a $logfile
echo "style_video_base is " $style_video_base | tee -a $logfile
echo "style_image  is" $style_image | tee -a $logfile
echo "style_image_base  is" $style_image_base | tee -a $logfile
echo "extension is" $extension | tee -a $logfile
echo "output dir is" $filename-$DATE | tee -a $logfile
echo ""

#For non-Nvidia GPU, use clnn. Note: You have to have the given backend installed in order to use it. [nn] $cr > " backend
backend=cudnn

if [ "$backend" == "cudnn" ]; then
  echo ""
  read -p "This algorithm needs a lot of memory. \
  Please enter a resolution at which the video should be processed, \
  in the format w:h, or leave blank to use the original resolution $cr > " resolution
else
  echo "Unknown backend."
  exit 1
fi

# Save frames of the video as individual image files
if [ -z $resolution ]; then
  $FFMPEG -i $1 /content/vid/${style_video_base}/frames/frame_%04d.ppm
  resolution=default  #how can we get actual numbers for this even if they are 'defaults'?
else
  $FFMPEG -i $1 -vf scale=$resolution /content/vid/${style_video_base}/frames/frame_%04d.ppm
fi

echo ""
read -p "How much do you want to weight the style reconstruction term? \
Default value: 1e2 for a resolution of 450x350. Increase for a higher resolution. \
[1e2] $cr > " style_weight
style_weight=${style_weight:-1e2}

temporal_weight=1e3

echo ""
read -p "Enter the zero-indexed ID of the GPU to use, or -1 for CPU mode (very slow!).\
 [0] $cr > " gpu
gpu=${gpu:-0}

echo "------------------------------"
echo "resolution : " ${resolution}  | tee -a $logfile
echo "style_weight : " ${style_weight}  | tee -a $logfile
echo " temporal_weight : " ${temporal_weight}  | tee -a $logfile


echo ""
echo "Computing optical flow. This may take a while..."
bash makeOptFlow.sh /content/vid/${style_video_base}/frames/frame_%04d.ppm /content/vid/${style_video_base}/flow/flow_$resolution


echo "optical flow finished at $(date "+%Y-%m-%d %H:%M:%S") " | tee -a $logfile

iterations_initial=1000
iterations=400

echo "iterations on initial frame: " $iterations_initial | tee -a $logfile
echo "iterations on subsequent frames: " $iterations | tee -a $logfile

# Perform style transfer
th artistic_video.lua \
-content_pattern /content/vid/${style_video_base}/frames/frame_%04d.ppm \
-flow_pattern /content/vid/${style_video_base}/flow/flow_${resolution}/backward_[%d]_{%d}.flo \
-flowWeight_pattern /content/vid/${style_video_base}/flow/flow_${resolution}/reliable_[%d]_{%d}.pgm \
-style_weight $style_weight \
-temporal_weight $temporal_weight \
-num_iterations $iterations_initial,$iterations \
-output_folder /content/output/${filename}-$DATE/ \
-style_image /content/img/$style_image \
-backend $backend \
-gpu $gpu \
-cudnn_autotune \
-number_format %04d

echo "style transfer finished at $(date "+%Y-%m-%d %H:%M:%S") " | tee -a $logfile

# Create video from output images.
$FFMPEG -i /content/output/${filename}-$DATE/out-%04d.png /content/output/${filename}-$DATE/${filename}-$DATE-stylized.$extension

