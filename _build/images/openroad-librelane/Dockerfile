# SPDX-FileCopyrightText: 2022-2026 Harald Pretl and Georg Zachl
# Johannes Kepler University, Department for Integrated Circuits
# SPDX-License-Identifier: Apache-2.0
#######################################################################
# Compile OpenROAD for LibreLane
#######################################################################
ARG BASE_IMAGE_BUILD="registry.iic.jku.at:5000/iic-osic-tools:base-dev"
FROM ${BASE_IMAGE_BUILD} AS openroad-librelane
ARG OPENROAD_LIBRELANE_REPO_URL="https://github.com/The-OpenROAD-Project/OpenROAD.git"
ARG OPENROAD_LIBRELANE_REPO_COMMIT="887d6c59d1c3a327a342b79d0154f17624417379"
ARG OPENROAD_LIBRELANE_NAME="openroad-librelane"
RUN --mount=type=bind,source=images/openroad-librelane,target=/images/openroad-librelane \
    bash /images/openroad-librelane/scripts/install.sh
