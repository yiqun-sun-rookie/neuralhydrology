import matplotlib.pyplot as plt
import pandas as pd
import os

# Data from the summary
data = {
    'Model': ['L1 (Rain Only)', 'L4 (AR, 1h)', 'L5 (AR, 6h)', 'L5 (AR, 12h)', 'L5 (AR, 24h)', 'L6 (Seq2Seq)'],
    'NSE': [-0.25, 0.97, 0.76, 0.82, 0.73, -0.27],
    'RMSE': [79.34, 12.49, 34.52, 29.98, 36.54, 80.17]
}

df = pd.DataFrame(data)

# Plotting
fig, ax1 = plt.subplots(figsize=(12, 6))

# Bar chart for NSE
color = 'tab:blue'
ax1.set_xlabel('Model Experiment')
ax1.set_ylabel('NSE (Higher is Better)', color=color)
bars = ax1.bar(df['Model'], df['NSE'], color=color, alpha=0.7, label='NSE')
ax1.tick_params(axis='y', labelcolor=color)
ax1.set_ylim(-0.5, 1.1)

# Add value labels on bars
for bar in bars:
    height = bar.get_height()
    ax1.text(bar.get_x() + bar.get_width()/2., height,
             f'{height:.2f}',
             ha='center', va='bottom' if height > 0 else 'top')

# Line chart for RMSE
ax2 = ax1.twinx()  # instantiate a second axes that shares the same x-axis
color = 'tab:red'
ax2.set_ylabel('RMSE (Lower is Better)', color=color)  # we already handled the x-label with ax1
line = ax2.plot(df['Model'], df['RMSE'], color=color, marker='o', linewidth=2, label='RMSE')
ax2.tick_params(axis='y', labelcolor=color)

# Title and Layout
plt.title('Nam Ou (Kuwei) Model Performance Comparison')
fig.tight_layout()  # otherwise the right y-label is slightly clipped

# Save
output_path = 'namou_kuwei_performance.png'
plt.savefig(output_path)
print(f"Chart saved to {os.path.abspath(output_path)}")
