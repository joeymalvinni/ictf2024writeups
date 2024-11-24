{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "python-environment";

  buildInputs = [
    pkgs.python311
    pkgs.python311Packages.numpy
    pkgs.python311Packages.pandas
    pkgs.python311Packages.matplotlib
    pkgs.python311Packages.scipy
    pkgs.python311Packages.scikit-learn
    pkgs.python311Packages.tensorflow
    pkgs.python311Packages.pyqt5
    pkgs.python311Packages.requests
    pkgs.python311Packages.flask
    pkgs.python311Packages.django
    pkgs.python311Packages.sqlalchemy
    pkgs.python311Packages.fastapi
    pkgs.python311Packages.pytorch
    pkgs.python311Packages.networkx
    pkgs.python311Packages.jupyter
    pkgs.python311Packages.notebook
    pkgs.wget
    pkgs.python312Packages.piexif
    pkgs.perl538Packages.ImageExifTool
    pkgs.python312Packages.pillow
    pkgs.python312Packages.opencv4

    pkgs.zsh
    pkgs.zsh-autosuggestions
  ];

  shellHook = ''
    export SHELL=$(which zsh)
    zsh
  '';
}
