# Phxm - Phoenix Manager, A Project Manager for Neovim

> [!NOTE]
> Not adapted for public usability. Integrated into my personal setup.

This is my personal project manager for Neovim. It allows you to switch between projects and files easily. Relies on `Telescope` for many functions in my use. The idea of `Phxm` is to be a base allowing for easy inclusion of other software that solves the specific needs, such as file management, git management, etc.

It handles session session managment seamlessly. Each project has its own session that is loaded and unloaded at project switch.

_Phxm_ has 3 or 4 main components: ... dynkey, keypoint, permtermbuf, ...

> [!NOTE]
> This is a work in progress. The code is not well organized and the documentation is incomplete. Primarily written for my own use, but I aim to progressively refine it to perhaps make it usable for others.

## Current state

There is not much to see yet, as this concept, at the moment, is not presented in any fairly approachable way.

## History

This was quickly developed to allow me to be effective using Linux by facilitating project spaces and easy switching between them. Not much attention was put on making this nice, as I first had to get up and running effectively with Linux and Neovim. As I developed this, I also learned about Linux and Neovim in general, and this project matured in tandem with my increasing knowledge.

This project was first called ProManager, but as I was just about to finish a few remaining things, I discovered deal-breaking bugs in the code that left me in a state of hopelessness and despair. Remember, this was not a project developed in the save environment of a working IDE. This project was developed to make the very IDE I needed to keep my sanity in approaching my more complex projects and general computer activity that required a lot of context switching (just developing a Neovim plugin requires context switching between plugin sources and plugin specs, and layer that with the development of 3 plugin modules meant to interconnect, for example). So, I was almost done with a working version of ProManager, awaiting eagerly to continue with my other projects, but the deal-breaking bugs left me realizing I had to do major refactoring and more work. I sort of started over from scratch, but importing the good parts of the previous version. Thus, Phoenix Manager was born---it rose from the ashes of ProManager. I was not going to let this defeat me, and I was not going to give up on my dream of having a project manager that would allow me to work in a more efficient way. I had already seen enough of the capabilities of Neovim and fallen in love with it, and there was no way I was going to give up.

I started with nothing but the core Neovim with kickstart.nvim, and would start building the project manager I desired. The idea was to build an environment I do not have to leave, meaning I utilize Neovim's capability of terminal buffers, for example, to enter the terminal and then switch back into Neovim editor mode. I came to integrate all sorts of tools like file filemanager (lf), github interface (lazygit), multiplexer (tmux) etc.

Having been a sporadic Linux user for many years, but only very marginally using it, I finally decided to switch completely to Linux. The more I grew accustomed to the terminal, the more I realized the traditional tools and Unix philosophy in general would satisfy my needs. I did away with VSCode and settled with Neovim as the one and only editor I am going to ever use for the rest of my life. Navigating Linux and keeping track of different contexts proved to be a challenge, non the least to my short and long term memory. I would end up layers deep and forget where I started.

I developed this project manager to facilitate defining project spaces and switching between them (for example, backspace in normal mode switches to the previous project). Key bindings can be assigned to projects and buffers have keys bound to them dynamically. _Telescope_ is a game changer since I used Linux many years ago, and _Telescope_ is perhaps part of the engine of this project manager, as it allows for ultra fast navigation among projects and files within project spaces. However, before I realized the power of _Telescope_, I built the project manager to support easy switching by keybindings, and that functionality remains.

A note on further functionality that involves _Tree-sitter_. That section of the code will later be factored into freestanding plugins.

There are experimental features that will need to be improved.

## Events

preSwitchToProject - Before switching to a project.

postSwitchToProject - After switching to a project.

[This list is incomplete and maybe outdated.]
