from scipy import signal
import scipy.io.wavfile as wavfile
import numpy as np
import matplotlib.pyplot as plt
from scipy.fftpack import fft, fftfreq

def convert_to_pcm(filepath, instrument):

    fs_old, data = wavfile.read(filepath)

    # DOWNSAMPLE DATA
    fs_new = 8000

    gcd = np.gcd(fs_old, fs_new)
    up = fs_new // gcd
    down = fs_old // gcd

    x_resampled = signal.resample_poly(data, up, down)

    # FFT ON RESAMPLED SIGNAL
    fourier = fft(x_resampled)
    freqs = fftfreq(len(x_resampled), d=1/fs_new)

    # KEEP ONLY POSITIVE FREQUENCIES
    end = len(freqs) // 2

    x_axis = freqs[:end]
    y_axis = np.abs(fourier[:end])
    '''
    plt.xlabel("Frequency (Hz)")
    plt.ylabel("Amplitude")
    plt.plot(x_axis, y_axis)
    #plt.show() 
    '''
    # normalize + convert
    x = x_resampled.astype(np.float32)
    x = x / np.max(np.abs(x))

    samples = (x * 32767).astype("<i2")

    plt.plot(samples[:, 0])
    #plt.show()

    samples.tofile(f"{filepath}_{instrument}.pcm")
