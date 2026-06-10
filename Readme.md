Final Project for CS448z

Elton Manchester and Wesley Larlarb

Reimplementing Scraping and Rolling Sounds as per Agarwal et al
https://arxiv.org/pdf/2112.08984

For this project, we reimplemnented the scraping and rolling sound synthesis model described in the above paper for purposes of both reproduction and in order to adapt it to realtime uses. We worked in the ChuGL audiovisual programming environment:
https://chuck.stanford.edu/chugl/

Our steps consisted in
- Implementing a fractal noise generation algorithm (see Heightmap.wgsl) which replaces the physically measured heightmaps in the original paper. We gave the noise tunable parameters so that artists could experiment with different qualities of the noise, and also allow these parameters to be adjusted in realtime during the demo, which could allow for rapid iteration or even responsive manipulation during gameplay.
- Creating a simple physics simulation of a ball rolling around on a table with interactive control via rotating the table (see ScrapingNoise.ck).
- Sampling the ball position, velocity, heightmap and its derivatives with interpolation across graphics frames to create a smooth trajectory when playing at the desired audio sample rate. Using these sampled values to compute the relevant derivatives and forces (vertical and COM offset) from the given paper (also in ScrapingNoise.ck).
- Recording impulse responses of a wooden box at regular intervals (see IRSampling.jpeg). Interpolating between these impulse responses based on the location of the ball on the board, with care being taken to update the interpolated impulse response in chunks in order to avoid dropping audio samples when playing at the realtime rate.

To run the simulation, you'll need to have the latest version of chuck installed:
https://chuck.stanford.edu/

Then, run "chuck ScrapingNoise.ck".

See Labyrinth.mov for a demo