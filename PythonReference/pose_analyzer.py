import cv2
import mediapipe as mp
import numpy as np
import os
import sys
import subprocess
import math
try:
    from moviepy.editor import VideoFileClip
    MOVIEPY_AVAILABLE = True
except ImportError:
    MOVIEPY_AVAILABLE = False
    print("Warning: MoviePy not available. Video compression will be disabled.")
import argparse

class PoseAnalyzer:
    def __init__(self, side='left'):
        """
        Initialize Pose Analyzer (for lat pulldown)
        Args:
            side: 'left' or 'right' - which side of the body to analyze (default: 'left')
        """
        self.side = side.lower()
        if self.side not in ['left', 'right']:
            raise ValueError("side must be 'left' or 'right'")
        
        self.mp_drawing = mp.solutions.drawing_utils
        self.mp_pose = mp.solutions.pose
        
        # Customize drawing style
        self.drawing_spec = self.mp_drawing.DrawingSpec(thickness=2, circle_radius=2)
        
        # Select landmarks based on side
        if self.side == 'left':
            self.shoulder_landmark = self.mp_pose.PoseLandmark.LEFT_SHOULDER
            self.elbow_landmark = self.mp_pose.PoseLandmark.LEFT_ELBOW
            self.wrist_landmark = self.mp_pose.PoseLandmark.LEFT_WRIST
            self.hip_landmark = self.mp_pose.PoseLandmark.LEFT_HIP
        else:  # right
            self.shoulder_landmark = self.mp_pose.PoseLandmark.RIGHT_SHOULDER
            self.elbow_landmark = self.mp_pose.PoseLandmark.RIGHT_ELBOW
            self.wrist_landmark = self.mp_pose.PoseLandmark.RIGHT_WRIST
            self.hip_landmark = self.mp_pose.PoseLandmark.RIGHT_HIP
        
        # Define which landmarks to show
        self.landmark_list = [
            self.shoulder_landmark,
            self.elbow_landmark,
            self.wrist_landmark,
            self.hip_landmark
        ]
        
        # Define connections between landmarks
        self.custom_connections = frozenset([
            (self.shoulder_landmark, self.hip_landmark)
        ])
        
        self.pose = self.mp_pose.Pose(
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5)

    def calculate_angle(self, a, b, c):
        """
        Calculate the angle between three points.
        Args:
            a: first point [x, y]
            b: mid point [x, y] (the joint)
            c: end point [x, y]
        Returns:
            angle in degrees
        """
        a = np.array(a)
        b = np.array(b)
        c = np.array(c)
        
        radians = np.arctan2(c[1]-b[1], c[0]-b[0]) - np.arctan2(a[1]-b[1], a[0]-b[0])
        angle = np.abs(radians*180.0/np.pi)
        
        if angle > 180.0:
            angle = 360-angle
            
        return angle

    def extend_line_to_frame(self, point1, point2, width, height):
        # Convert points to numpy arrays
        p1 = np.array(point1)
        p2 = np.array(point2)
        
        # Calculate direction vector
        direction = p2 - p1
        direction = direction / np.linalg.norm(direction)
        
        # Calculate distances to each edge
        distances = []
        points = []
        
        # Top edge (y = 0)
        if direction[1] != 0:
            t = -p1[1] / direction[1]
            if t > 0:
                x = p1[0] + t * direction[0]
                if 0 <= x <= width:
                    distances.append(t)
                    points.append((int(x), 0))
        
        # Bottom edge (y = height)
        if direction[1] != 0:
            t = (height - p1[1]) / direction[1]
            if t > 0:
                x = p1[0] + t * direction[0]
                if 0 <= x <= width:
                    distances.append(t)
                    points.append((int(x), height))
        
        # Left edge (x = 0)
        if direction[0] != 0:
            t = -p1[0] / direction[0]
            if t > 0:
                y = p1[1] + t * direction[1]
                if 0 <= y <= height:
                    distances.append(t)
                    points.append((0, int(y)))
        
        # Right edge (x = width)
        if direction[0] != 0:
            t = (width - p1[0]) / direction[0]
            if t > 0:
                y = p1[1] + t * direction[1]
                if 0 <= y <= height:
                    distances.append(t)
                    points.append((width, int(y)))
        
        if not points:
            return point1, point2
        
        # Find the furthest point
        max_dist_idx = np.argmax(distances)
        furthest_point = points[max_dist_idx]
        
        # Calculate the opposite direction to extend the line in the other direction
        opposite_direction = -direction
        opposite_distances = []
        opposite_points = []
        
        # Top edge (y = 0)
        if opposite_direction[1] != 0:
            t = -p2[1] / opposite_direction[1]
            if t > 0:
                x = p2[0] + t * opposite_direction[0]
                if 0 <= x <= width:
                    opposite_distances.append(t)
                    opposite_points.append((int(x), 0))
        
        # Bottom edge (y = height)
        if opposite_direction[1] != 0:
            t = (height - p2[1]) / opposite_direction[1]
            if t > 0:
                x = p2[0] + t * opposite_direction[0]
                if 0 <= x <= width:
                    opposite_distances.append(t)
                    opposite_points.append((int(x), height))
        
        # Left edge (x = 0)
        if opposite_direction[0] != 0:
            t = -p2[0] / opposite_direction[0]
            if t > 0:
                y = p2[1] + t * opposite_direction[1]
                if 0 <= y <= height:
                    opposite_distances.append(t)
                    opposite_points.append((0, int(y)))
        
        # Right edge (x = width)
        if opposite_direction[0] != 0:
            t = (width - p2[0]) / opposite_direction[0]
            if t > 0:
                y = p2[1] + t * opposite_direction[1]
                if 0 <= y <= height:
                    opposite_distances.append(t)
                    opposite_points.append((width, int(y)))
        
        if not opposite_points:
            return furthest_point, point2
        
        # Find the furthest point in the opposite direction
        max_opposite_dist_idx = np.argmax(opposite_distances)
        furthest_opposite_point = opposite_points[max_opposite_dist_idx]
        
        return furthest_point, furthest_opposite_point

    def compress_to_mp4(self, input_path, output_path):
        """Compress AVI to MP4 using moviepy"""
        try:
            # Check if input file exists
            if not os.path.exists(input_path):
                print(f"Error: Input file {input_path} does not exist")
                return False
            
            print("\nCompressing video to MP4...")
            
            # Get original file size
            input_size = os.path.getsize(input_path) / (1024*1024)  # MB
            
            # Load video
            video = VideoFileClip(input_path)
            
            # Write compressed video
            video.write_videofile(
                output_path,
                codec='libx264',
                audio_codec='aac',
                bitrate='2000k',
                fps=video.fps,
                threads=4,
                preset='medium'
            )
            
            # Close video
            video.close()
            
            # Get compressed file size
            output_size = os.path.getsize(output_path) / (1024*1024)  # MB
            compression_ratio = (1 - (output_size / input_size)) * 100
            
            print(f"\nCompression complete!")
            print(f"Original size: {input_size:.2f} MB")
            print(f"Compressed size: {output_size:.2f} MB")
            print(f"Compression ratio: {compression_ratio:.1f}%")
            
            # Remove original AVI file
            os.remove(input_path)
            print(f"Removed original AVI file: {input_path}")
            
            return True
            
        except Exception as e:
            print(f"Error during compression: {str(e)}")
            return False

    def process_video(self, input_path, output_path, preview=False, compress=True):
        try:
            cap = cv2.VideoCapture(input_path)
            if not cap.isOpened():
                print("Error: Could not open video file")
                return
            
            # Get video properties
            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            fps = int(cap.get(cv2.CAP_PROP_FPS))
            
            # Create output path in outputs directory
            script_dir = os.path.dirname(os.path.abspath(__file__))
            outputs_dir = os.path.join(script_dir, 'outputs')
            os.makedirs(outputs_dir, exist_ok=True)  # Create outputs directory if it doesn't exist
            output_path = os.path.join(outputs_dir, output_path)
            print(f"\nAttempting to save video to: {output_path}")
            
            # Try different codecs
            codecs = [
                ('H264', '.mp4'),  # Try H.264 first
                ('avc1', '.mp4'),  # Then AVC1
                ('mp4v', '.mp4'),  # Then regular MP4V
                ('XVID', '.avi'),  # Fallback to AVI
                ('MJPG', '.avi')   # Last resort
            ]
            
            out = None
            for codec, ext in codecs:
                try:
                    test_path = os.path.splitext(output_path)[0] + ext
                    print(f"\nTrying codec {codec} with output: {test_path}")
                    fourcc = cv2.VideoWriter_fourcc(*codec)
                    # Try with different parameters for better compatibility
                    out = cv2.VideoWriter(
                        test_path,
                        fourcc,
                        fps,
                        (width, height),
                        isColor=True
                    )
                    if out.isOpened():
                        output_path = test_path
                        print(f"Successfully created video writer with codec: {codec}")
                        break
                    else:
                        out.release()
                except Exception as e:
                    print(f"Failed with codec {codec}: {str(e)}")
                    if out:
                        out.release()
            
            if not out or not out.isOpened():
                print("Error: Could not create output video file with any codec")
                return
            
            # Get total frame count
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            print(f"\nTotal frames in video: {total_frames}")
            print(f"Video FPS: {fps}")
            print(f"Expected duration: {total_frames/fps:.2f} seconds")
            print("\nProcessing video...")
            
            frame_count = 0
            while cap.isOpened():
                ret, frame = cap.read()
                if not ret:
                    print(f"\nReached end of video after {frame_count} frames")
                    break

                # Process frame
                image = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                image.flags.writeable = False
                results = self.pose.process(image)
                image.flags.writeable = True
                image = cv2.cvtColor(image, cv2.COLOR_RGB2BGR)
                
                try:
                    landmarks = results.pose_landmarks.landmark
                    
                    # Get coordinates (using selected side)
                    shoulder = [landmarks[self.shoulder_landmark.value].x,
                              landmarks[self.shoulder_landmark.value].y]
                    elbow = [landmarks[self.elbow_landmark.value].x,
                            landmarks[self.elbow_landmark.value].y]
                    wrist = [landmarks[self.wrist_landmark.value].x,
                            landmarks[self.wrist_landmark.value].y]
                    hip = [landmarks[self.hip_landmark.value].x,
                          landmarks[self.hip_landmark.value].y]
                    
                    # Calculate angles
                    elbow_angle = self.calculate_angle(shoulder, elbow, wrist)
                    shoulder_angle = self.calculate_angle(hip, shoulder, elbow)
                    
                    # Visualize
                    h, w, c = image.shape
                    
                    # Convert coordinates to pixel values
                    shoulder_px = (int(shoulder[0] * w), int(shoulder[1] * h))
                    elbow_px = (int(elbow[0] * w), int(elbow[1] * h))
                    wrist_px = (int(wrist[0] * w), int(wrist[1] * h))
                    hip_px = (int(hip[0] * w), int(hip[1] * h))
                    
                    # Draw extended line first (background)
                    extended_line_points = self.extend_line_to_frame(wrist_px, elbow_px, w, h)
                    cv2.line(image, extended_line_points[0], extended_line_points[1], (0, 255, 255), 2)
                    
                    # Draw skeleton and angles
                    for landmark in self.landmark_list:
                        x = int(landmarks[landmark.value].x * w)
                        y = int(landmarks[landmark.value].y * h)
                        cv2.circle(image, (x, y), 5, (255, 255, 255), -1)
                    
                    cv2.line(image, hip_px, shoulder_px, (0, 255, 255), 2)
                    cv2.line(image, shoulder_px, elbow_px, (255, 255, 0), 3)
                    cv2.line(image, elbow_px, wrist_px, (255, 255, 0), 3)
                    
                    cv2.circle(image, elbow_px, 10, (0, 0, 255), -1)
                    cv2.circle(image, shoulder_px, 10, (0, 0, 255), -1)
                    
                    cv2.putText(image, f"Elbow: {int(elbow_angle)}", 
                               (elbow_px[0]-50, elbow_px[1]+50),
                               cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
                    cv2.putText(image, f"Shoulder: {int(shoulder_angle)}", 
                               (shoulder_px[0]-50, shoulder_px[1]-30),
                               cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
                    
                except Exception as e:
                    print(f"\nFrame {frame_count} processing error: {e}")
                    # For frames where pose detection fails, write the original frame
                    image = frame
                
                # Write frame
                out.write(image)
                frame_count += 1
                
                # Show progress
                if frame_count % 30 == 0:
                    percent_done = (frame_count / total_frames) * 100
                    print(f"Processed {frame_count}/{total_frames} frames ({percent_done:.1f}%)")
                
                # Show preview if enabled
                if preview:
                    cv2.imshow('Preview', image)
                    if cv2.waitKey(1) & 0xFF == ord('q'):
                        print("\nProcessing interrupted by user")
                        break
            
            # Clean up
            cap.release()
            out.release()
            cv2.destroyAllWindows()
            
            # Verify file was created
            if os.path.exists(output_path):
                final_size = os.path.getsize(output_path) / (1024*1024)
                print(f"\nSuccess! Video saved to: {output_path}")
                print(f"File size: {final_size:.2f} MB")
                print(f"Processed frames: {frame_count}/{total_frames}")
                print(f"Actual duration: {frame_count/fps:.2f} seconds")
                
                # If the output is AVI and compression is enabled, try to compress it to MP4
                if compress and output_path.lower().endswith('.avi'):
                    mp4_path = os.path.splitext(output_path)[0] + '.mp4'
                    if self.compress_to_mp4(output_path, mp4_path):
                        print(f"\nSuccessfully compressed to MP4: {mp4_path}")
                    else:
                        print("\nFailed to compress to MP4, keeping original AVI file")
            else:
                print("\nError: Output file was not created")
            
        except Exception as e:
            print(f"\nError during video processing: {e}")
            sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Process video with pose analysis.')
    parser.add_argument('--input', type=str, default="/Users/kevinrooster/Downloads/shitlatpulldown.mov", help='Input video path')
    parser.add_argument('--output', type=str, default="analyzed_shitlatpulldown", help='Output video path')
    parser.add_argument('--side', type=str, default='left', choices=['left', 'right'], help='Which side to analyze (left or right)')
    parser.add_argument('--preview', action='store_true', help='Enable preview window')
    parser.add_argument('--no-compress', action='store_true', help='Disable compression')
    args = parser.parse_args()

    analyzer = PoseAnalyzer(side=args.side)
    analyzer.process_video(args.input, args.output, preview=args.preview, compress=not args.no_compress) 