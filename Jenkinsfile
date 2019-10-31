/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright 2019 Joyent, Inc.
 */

@Library('jenkins-joylib@v1.0.2') _


String buildMasterDaily = BRANCH_NAME == "master" ? "@daily" : ""

pipeline {

    agent {
        label '!virt:kvm && fs:pcfs && fs:ufs && jenkins_agent:2 && pkgsrc_arch:multiarch'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timestamps()
    }


    // Trigger a build of "master" periodically, given that we intentionally
    // do not spawn a new headnode build for every change to included
    // components: headnode builds are too big and slow for that.
    //
    // https://stackoverflow.com/a/44902622 provides a solution.
    triggers {
        cron(buildMasterDaily)
    }

    stages {
        stage('check') {
            steps{
                sh('make check')
            }
        }
        stage('build') {
            steps {
                sh('''
set -o errexit
set -o pipefail

# validate-buildenv checks for a delegated dataset, unnecessary for the
# headnode build.
export ENGBLD_SKIP_VALIDATE_BUILDENV=true

env

# TODO: Do we care to support these from the "headnode" freestyle job?
#if [[ -n "$CONFIGURE_BRANCHES" ]]; then
#    echo "${CONFIGURE_BRANCHES}" > configure-branches
#fi
#
#if [[ -n "$BUILD_SPEC_LOCAL" ]]; then
#    echo "$BUILD_SPEC_LOCAL" > build.spec.local
#    json < build.spec.local
#fi

# Ensure the 'gz-tools' image gets published.
export ENGBLD_BITS_UPLOAD_IMGAPI=true

# Note we intentionally use bits-upload-latest # so that our Manta path gets the
# 'latest-timestamp' override from our 'publish' target.
make print-STAMP all publish bits-upload-latest''')
            }
        }
    }

    post {
        always {
            joyMattermostNotification(channel: 'jenkins')
        }
    }

}
