import os
import sys
from PIL import Image, ImageDraw

def mask_icon():
    # Use relative path or find the artifact
    img_path = "/Users/hassan/.gemini/antigravity/brain/2ea441ab-d501-4b99-a366-9d8af455094c/resource_tracker_icon_1782742120120.jpg"
    if not os.path.exists(img_path):
        # Fallback to local copy if run in general context
        img_path = "build/app_icon_base.jpg"
        if not os.path.exists(img_path):
            print("Warning: Base app icon image not found. Skipping icon masking.")
            sys.exit(0)
        
    img = Image.open(img_path).convert("RGBA")
    
    # Bounding box of the inner squircle in the 1024x1024 image
    left = 168
    top = 168
    right = 856
    bottom = 856
    
    cropped = img.crop((left, top, right, bottom))
    w, h = cropped.size
    
    # Create mask for the rounded corners (squircle-like)
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    
    # Corner radius is approximately 150 pixels for a 688x688 cropped image.
    radius = 150
    draw.rounded_rectangle([0, 0, w, h], radius=radius, fill=255)
    
    # Apply mask
    cropped.putalpha(mask)
    
    # Create a standard 1024x1024 transparent canvas
    final_canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    
    # Scale the cropped squircle to standard macOS icon body size (824x824)
    target_size = 824
    scaled_icon = cropped.resize((target_size, target_size), Image.Resampling.LANCZOS)
    
    # Center it on the 1024x1024 canvas
    offset = (1024 - target_size) // 2
    final_canvas.paste(scaled_icon, (offset, offset), scaled_icon)
    
    # Save the result
    out_path = "build/app_icon_base_transparent.png"
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    final_canvas.save(out_path, "PNG")
    print(f"Success: Generated transparent icon at {out_path}")

if __name__ == "__main__":
    mask_icon()
