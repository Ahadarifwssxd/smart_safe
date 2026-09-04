import os, re
import sys

def process():
    count = 0
    for root, dirs, files in os.walk('lib'):
        for file in files:
            if not file.endswith('.dart'): continue
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            old_content = content
            content = re.sub(r'const\s+(TextStyle|BoxDecoration|Icon|Border|ColorScheme|Divider|Text|Positioned|Center|Padding|SizedBox|Row|Column|Container|Align|BoxShadow|Color|Drawer|AppBar|Scaffold|FloatingActionButton|ListTile|CircleAvatar|Card|ElevatedButton|OutlinedButton|TextButton)\(', r'\1(', content)
            content = re.sub(r'const\s+\[', r'[', content)
            
            if content != old_content:
                count += 1
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(content)
    print(f"Modified {count} files")

if __name__ == '__main__':
    process()
