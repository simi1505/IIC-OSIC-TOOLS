# SPDX-FileCopyrightText: 2022-2026 Harald Pretl and Georg Zachl
# Johannes Kepler University, Department for Integrated Circuits
# SPDX-License-Identifier: Apache-2.0
#######################################################################
# Compile vacask
#######################################################################
ARG TOOL_IMAGE_OPENVAF="registry.iic.jku.at:5000/iic-osic-tools:tool-openvaf-latest"
FROM ${TOOL_IMAGE_OPENVAF} AS vacask
ARG VACASK_REPO_URL="https://codeberg.org/arpadbuermen/VACASK.git"
ARG VACASK_REPO_COMMIT="02d518c3b3f4ccc23f4efc6db787fe1cd782a362"
ARG VACASK_NAME="vacask"
RUN --mount=type=bind,source=images/vacask,target=/images/vacask \
    bash /images/vacask/scripts/install.sh
