import matplotlib.pyplot as plt
import csv
import numpy as np
import simpleaudio as sa

x = []
y = []
frequency = []
fft= []


with open('audio.txt','r') as csvfile:
    plots = csv.reader(csvfile, delimiter=',')
    for row in plots:
        x.append(int(row[0]))
        y.append(int(row[1]))
        frequency.append(float(row[2]))
        fft.append(float(row[3]))

plt.subplot(3, 1, 1)
plt.plot(x,y, label='Loaded from file!')
plt.ylabel('y')
plt.xlabel('x')
plt.title('sound / time')
plt.legend()

plt.subplot(3, 1, 2)
plt.plot(frequency,fft, label='FFT!')
plt.ylabel('y')
plt.xlabel('x')
plt.title('amplitude/frequency')
plt.legend()

plt.show()

