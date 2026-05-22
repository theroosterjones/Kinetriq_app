import os
import cv2
import numpy as np
from flask import Flask, render_template, request, jsonify, send_file
from flask_cors import CORS
from werkzeug.utils import secure_filename
import mediapipe as mp
from datetime import datetime
import json
import sys

# Import the working analyzers
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from hacksquat_analyzer import HackSquatAnalyzer
from row_analyzer import RowAnalyzer
from pose_analyzer import PoseAnalyzer
from backsquat_analyzer import BackSquatAnalyzer

app = Flask(__name__)
CORS(app)  # Enable CORS for iOS app requests
max_content_length_mb = int(os.getenv('MAX_CONTENT_LENGTH_MB', '500'))
storage_root = os.getenv('APP_STORAGE_ROOT', '.')
app.config['MAX_CONTENT_LENGTH'] = max_content_length_mb * 1024 * 1024
app.config['UPLOAD_FOLDER'] = os.path.join(storage_root, 'uploads')
app.config['OUTPUT_FOLDER'] = os.path.join(storage_root, 'outputs')

# Ensure directories exist
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
os.makedirs(app.config['OUTPUT_FOLDER'], exist_ok=True)

ALLOWED_EXTENSIONS = {'mp4', 'avi', 'mov', 'mkv', 'wmv', 'flv', 'webm'}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

class FitnessAnalyzer:
    def __init__(self):
        self.mp_drawing = mp.solutions.drawing_utils
        self.mp_pose = mp.solutions.pose
        self.pose = self.mp_pose.Pose(
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        )
    
    def calculate_angle(self, a, b, c):
        """Calculate angle between three points"""
        a = np.array(a)
        b = np.array(b)
        c = np.array(c)
        radians = np.arctan2(c[1]-b[1], c[0]-b[0]) - np.arctan2(a[1]-b[1], a[0]-b[0])
        angle = np.abs(radians*180.0/np.pi)
        if angle > 180.0:
            angle = 360-angle
        return angle
    
    
    def analyze_squat(self, video_path, output_path):
        """Analyze squat form"""
        cap = cv2.VideoCapture(video_path)
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = int(cap.get(cv2.CAP_PROP_FPS))
        
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(output_path, fourcc, fps, (width, height))
        
        rep_count = 0
        form_score = 100
        feedback = []
        squat_state = 'top'  # 'top' = standing, 'bottom' = in the hole
        BOTTOM_ANGLE = 95
        TOP_ANGLE = 150
        
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break
            
            # Process frame
            image = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image.flags.writeable = False
            results = self.pose.process(image)
            image.flags.writeable = True
            image = cv2.cvtColor(image, cv2.COLOR_RGB2BGR)
            
            if results.pose_landmarks:
                landmarks = results.pose_landmarks.landmark
                
                # Get coordinates for squat analysis
                left_hip = [landmarks[self.mp_pose.PoseLandmark.LEFT_HIP.value].x,
                           landmarks[self.mp_pose.PoseLandmark.LEFT_HIP.value].y]
                right_hip = [landmarks[self.mp_pose.PoseLandmark.RIGHT_HIP.value].x,
                            landmarks[self.mp_pose.PoseLandmark.RIGHT_HIP.value].y]
                left_knee = [landmarks[self.mp_pose.PoseLandmark.LEFT_KNEE.value].x,
                            landmarks[self.mp_pose.PoseLandmark.LEFT_KNEE.value].y]
                right_knee = [landmarks[self.mp_pose.PoseLandmark.RIGHT_KNEE.value].x,
                             landmarks[self.mp_pose.PoseLandmark.RIGHT_KNEE.value].y]
                left_ankle = [landmarks[self.mp_pose.PoseLandmark.LEFT_ANKLE.value].x,
                             landmarks[self.mp_pose.PoseLandmark.LEFT_ANKLE.value].y]
                right_ankle = [landmarks[self.mp_pose.PoseLandmark.RIGHT_ANKLE.value].x,
                              landmarks[self.mp_pose.PoseLandmark.RIGHT_ANKLE.value].y]
                
                # Calculate angles
                left_knee_angle = self.calculate_angle(left_hip, left_knee, left_ankle)
                right_knee_angle = self.calculate_angle(right_hip, right_knee, right_ankle)
                avg_knee = (left_knee_angle + right_knee_angle) / 2
                # Rep counting: bottom = knee below 95°, top = knee above 150°
                if squat_state == 'top' and avg_knee < BOTTOM_ANGLE:
                    squat_state = 'bottom'
                elif squat_state == 'bottom' and avg_knee > TOP_ANGLE:
                    rep_count += 1
                    squat_state = 'top'
                
                # Draw pose landmarks
                self.mp_drawing.draw_landmarks(
                    image, results.pose_landmarks, self.mp_pose.POSE_CONNECTIONS)
                
                # Add angle text
                cv2.putText(image, f'Left Knee: {int(left_knee_angle)}', (10, 30),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
                cv2.putText(image, f'Right Knee: {int(right_knee_angle)}', (10, 60),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
                cv2.putText(image, f'Reps: {rep_count}', (10, 90),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
                cv2.putText(image, f'Form Score: {form_score}', (10, 120),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
            
            out.write(image)
        
        cap.release()
        out.release()
        
        return {
            'rep_count': rep_count,
            'form_score': form_score,
            'feedback': feedback
        }

@app.route('/')
def index():
    return render_template('fitness_index.html')

@app.route('/test')
def test():
    """Simple test endpoint to check if the app is running"""
    return jsonify({
        'status': 'running',
        'message': 'KevLines Fitness Analyzer is working!',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/status')
def api_status():
    """API status endpoint for iOS app"""
    return jsonify({
        'status': 'online',
        'version': '1.0.0',
        'supported_exercises': ['squat', 'hacksquat', 'row', 'lat_pulldown', 'backsquat'],
        'timestamp': datetime.now().isoformat()
    })

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({'error': 'No file uploaded'}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No file selected'}), 400
    
    if file and allowed_file(file.filename):
        filename = secure_filename(file.filename)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{timestamp}_{filename}"
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        file.save(filepath)
        
        return jsonify({
            'success': True,
            'filename': filename,
            'message': 'Video uploaded successfully'
        })
    
    return jsonify({'error': 'Invalid file type'}), 400

@app.route('/analyze', methods=['POST'])
def analyze_video():
    data = request.get_json()
    filename = data.get('filename')
    exercise_type = data.get('exercise_type', 'pushup')
    side = data.get('side', 'left')  # Default to 'left' for backward compatibility
    
    if not filename:
        return jsonify({'error': 'No filename provided'}), 400
    
    # Validate side parameter
    if side not in ['left', 'right']:
        side = 'left'  # Default to left if invalid
    
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    
    if not os.path.exists(filepath):
        return jsonify({'error': 'File not found'}), 404
    
    try:
        analyzer = FitnessAnalyzer()
        output_filename = f"analyzed_{exercise_type}_{filename}"
        output_path = os.path.join(app.config['OUTPUT_FOLDER'], output_filename)
        # Pass only filename so analyzers save to outputs/ (not outputs/outputs/)
        output_name_for_analyzer = output_filename
        
        if exercise_type == 'squat':
            results = analyzer.analyze_squat(filepath, output_path)
        elif exercise_type == 'hacksquat':
            hacksquat_analyzer = HackSquatAnalyzer(side=side)
            hacksquat_analyzer.process_video(filepath, output_name_for_analyzer, preview=False, compress=True)
            results = {
                'message': 'Hack squat analysis completed', 
                'output_file': output_filename,
                'rep_count': 0,  # TODO: Implement rep counting for hack squat
                'form_score': 85,  # TODO: Implement form scoring for hack squat
                'feedback': ['Hack squat analysis completed successfully']
            }
        elif exercise_type == 'row':
            row_analyzer = RowAnalyzer(side=side)
            row_rep_count = row_analyzer.process_video(filepath, output_name_for_analyzer, preview=False, compress=True)
            results = {
                'message': 'Row analysis completed', 
                'output_file': output_filename,
                'rep_count': row_rep_count if isinstance(row_rep_count, int) else 0,
                'form_score': 85,  # TODO: Implement form scoring for row
                'feedback': ['Row analysis completed successfully']
            }
        elif exercise_type == 'lat_pulldown':
            pose_analyzer = PoseAnalyzer(side=side)
            pose_analyzer.process_video(filepath, output_name_for_analyzer, preview=False, compress=True)
            results = {
                'message': 'Lat pulldown analysis completed', 
                'output_file': output_filename,
                'rep_count': 0,  # TODO: Implement rep counting for lat pulldown
                'form_score': 85,  # TODO: Implement form scoring for lat pulldown
                'feedback': ['Lat pulldown analysis completed successfully']
            }
        elif exercise_type == 'backsquat':
            backsquat_analyzer = BackSquatAnalyzer(side=side)
            backsquat_analyzer.process_video(filepath, output_name_for_analyzer, preview=False, compress=True)
            results = {
                'message': 'Back squat analysis completed', 
                'output_file': output_filename,
                'rep_count': 0,  # TODO: Implement rep counting for back squat
                'form_score': 85,  # TODO: Implement form scoring for back squat
                'feedback': ['Back squat analysis completed successfully']
            }
        else:
            return jsonify({'error': 'Unsupported exercise type. Supported types: squat, hacksquat, row, lat_pulldown, backsquat'}), 400
        
        return jsonify({
            'success': True,
            'results': results,
            'output_file': output_filename
        })
        
    except Exception as e:
        return jsonify({'error': f'Analysis failed: {str(e)}'}), 500

@app.route('/download/<filename>')
def download_file(filename):
    filepath = os.path.join(app.config['OUTPUT_FOLDER'], filename)
    if os.path.exists(filepath):
        return send_file(filepath, as_attachment=True)
    # Analyzers often output .mp4 even when upload was .mov; try alternate extension
    base, ext = os.path.splitext(filename)
    alt_ext = '.mp4' if ext.lower() == '.mov' else '.mov'
    alt_path = os.path.join(app.config['OUTPUT_FOLDER'], base + alt_ext)
    if os.path.exists(alt_path):
        return send_file(alt_path, as_attachment=True, download_name=filename)
    return jsonify({'error': 'File not found'}), 404

if __name__ == '__main__':
    print("🏋️ Starting KevLines Fitness Analyzer")
    print("📱 Access from other machines using your computer's IP address")
    print("🌐 Web interface: http://0.0.0.0:3000")
    print("\n" + "="*60)
    
    app.run(debug=False, host='0.0.0.0', port=3000) 