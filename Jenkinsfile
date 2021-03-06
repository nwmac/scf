#!/usr/bin/env groovy
// vim: set et sw=4 ts=4 :

String ipAddress() {
    return sh(returnStdout: true, script: "ip -4 -o addr show eth0 | awk '{ print \$4 }' | awk -F/ '{ print \$1 }'").trim()
}

String domain() {
    return ipAddress() + ".nip.io"
}

String jobBaseName() {
    return env.JOB_BASE_NAME.toLowerCase()
}

void runTest(String testName) {
    sh """
        kube_overrides() {
            ruby <<EOF
                require 'yaml'
                require 'json'
                domain = '${domain()}'
                obj = YAML.load_file('\$1')
                obj['spec']['containers'].each do |container|
                    container['env'].each do |env|
                        value = env['value']
                        value = domain          if env['name'] == 'DOMAIN'
                        value = "tcp.#{domain}" if env['name'] == 'TCP_DOMAIN'
                        env['value'] = value.to_s
                    end
                end
                puts obj.to_json
EOF
        }

        image=\$(awk '\$1 == "image:" { print \$2 }' "unzipped/kube/cf/bosh-task/${testName}.yaml" | tr -d '"')

        kubectl run \
            --namespace=${jobBaseName()}-${BUILD_NUMBER}-scf \
            --attach \
            --restart=Never \
            --image=\${image} \
            --overrides="\$(kube_overrides "unzipped/kube/cf/bosh-task/${testName}.yaml")" \
            "${testName}"
    """
}

String distSubDir() {
    try {
        "${CHANGE_ID}"
        return 'prs/'
    } catch (Exception ex) {
        switch (env.BRANCH_NAME) {
            case 'develop':
                return 'develop/'
            case 'master':
                return 'master/'
            default:
                return 'branches/'
        }
    }
}

String distPrefix() {
    try {
        return "PR-${CHANGE_ID}-"
    } catch (Exception ex) {
        if (env.BRANCH_NAME == 'develop' || env.BRANCH_NAME == 'master') {
            return ''
        }
        return java.net.URLEncoder.encode("${BRANCH_NAME}-", "UTF-8")
    }
}

pipeline {
    agent { label ((["scf"] + (params.AGENT_LABELS ? params.AGENT_LABELS : "").tokenize()).join("&&")) }
    options {
        ansiColor('xterm')
        skipDefaultCheckout() // We do our own checkout so it can be disabled
        timestamps()
        timeout(time: 10, unit: 'HOURS')
        ws('scf')
    }
    parameters {
        booleanParam(
            name: 'SKIP_CHECKOUT',
            defaultValue: false,
            description: 'Skip the checkout step for faster iteration',
        )
        booleanParam(
            name: 'WIPE',
            defaultValue: false,
            description: 'Remove all existing sources and start from scratch',
        )
        booleanParam(
            name: 'CLEAN',
            defaultValue: true,
            description: 'Remove build artifacts that should normally not be reused',
        )
        booleanParam(
            name: 'PUBLISH_DOCKER',
            defaultValue: true,
            description: 'Enable publishing to docker',
        )
        booleanParam(
            name: 'PUBLISH_S3',
            defaultValue: true,
            description: 'Enable publishing to amazon s3',
        )
        booleanParam(
            name: 'TEST_SMOKE',
            defaultValue: true,
            description: 'Run smoke tests',
        )
        booleanParam(
            name: 'TEST_BRAIN',
            defaultValue: true,
            description: 'Run SATS (SCF Acceptance Tests)',
        )
        booleanParam(
            name: 'TEST_CATS',
            defaultValue: false,
            description: 'Run CATS (Cloud Foundry Acceptance Tests)',
        )
        booleanParam(
            name: 'TAR_SOURCES',
            defaultValue: false,
            description: 'Tar sources',
        )
        booleanParam(
            name: 'COMMIT_SOURCES',
            defaultValue: false,
            description: 'Push sources to obs',
        )
        credentials(
            name: 'OBS_CREDENTIALS',
            description: 'Password for build.opensuse.org',
            defaultValue: 'osc-alfred-jenkins',
        )
        credentials(
            name: 'S3_CREDENTIALS',
            description: 'AWS access key / secret key used for publishing',
            defaultValue: 'cred-s3-scf',
        )
        string(
            name: 'S3_REGION',
            description: 'AWS S3 region the target bucket is in',
            defaultValue: 'us-east-1',
        )
        string(
            name: 'S3_BUCKET',
            description: 'AWS S3 bucket to publish to',
            defaultValue: 'cf-opensusefs2',
        )
        string(
            name: 'S3_PREFIX',
            description: 'AWS S3 prefix to publish to',
            defaultValue: 'scf/config/',
        )
        credentials(
            name: 'DOCKER_CREDENTIALS',
            description: 'Docker credentials used for publishing',
            defaultValue: 'cred-docker-scf',
        )
        string(
            name: 'FISSILE_DOCKER_REGISTRY',
            defaultValue: '',
            description: 'Docker registry to publish to',
        )
        string(
            name: 'FISSILE_DOCKER_ORGANIZATION',
            defaultValue: 'splatform',
            description: 'Docker organization to publish to',
        )
        string(
            name: 'FISSILE_STEMCELL',
            defaultValue: '',
            description: 'Override the .envrc configured stemcell. .envrc is used if left blank.',
        )
        string(
            name: 'FISSILE_STEMCELL_VERSION',
            defaultValue: '',
            description: 'Override the .envrc configured stemcell version. .envrc is used if left blank.',
        )
        booleanParam(
            name: 'TRIGGER_SLES_BUILD',
            defaultValue: false,
            description: 'Trigger a SLES version of this job',
        )
        string(
            name: 'AGENT_LABELS',
            defaultValue: '',
            description: 'Extra labels for Jenkins slave selection',
        )
    }

    environment {
        FISSILE_DOCKER_REGISTRY = "${params.FISSILE_DOCKER_REGISTRY}"
        FISSILE_DOCKER_ORGANIZATION = "${params.FISSILE_DOCKER_ORGANIZATION}"
        FISSILE_STEMCELL = "${params.FISSILE_STEMCELL}"
        FISSILE_STEMCELL_VERSION = "${params.FISSILE_STEMCELL_VERSION}"
    }

    stages {
        stage('trigger_sles_build') {
          when {
                expression { return params.TRIGGER_SLES_BUILD }
          }
          steps {
            build job: 'scf-sles-trigger', wait: false, parameters: [string(name: 'JOB_NAME', value: env.JOB_NAME)]
          }
        }
        stage('wipe') {
            when {
                expression { return params.WIPE }
            }
            steps {
                deleteDir()
            }
        }
        stage('clean') {
            when {
                expression { return params.CLEAN }
            }
            steps {
                sh '''
                    kubectl get namespace | awk '/-scf|-uaa/ {print $1}' | xargs --no-run-if-empty kubectl delete ns
                    while kubectl get namespace | grep '-scf|-uaa'; do
                        sleep 1
                    done

                    docker images --format="{{.Repository}}:{{.Tag}}" | \
                        grep -E '/scf-|/uaa-|^uaa-role-packages:|^scf-role-packages:' | \
                        xargs --no-run-if-empty docker rmi
                '''
            }
        }
        stage('checkout') {
            when {
                expression { return (!params.SKIP_CHECKOUT) || params.WIPE }
            }
            steps {
                sh '''
                    git config --global --replace-all submodule.fetchJobs 0
                '''
                checkout scm
            }
        }
        stage('tools') {
            steps {
                sh '''
                    set -e +x
                    source ${PWD}/.envrc
                    set -x
                    unset HCF_PACKAGE_COMPILATION_CACHE
                    make ${FISSILE_BINARY}
                '''
            }
        }
        stage('build') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: params.DOCKER_CREDENTIALS,
                    usernameVariable: 'DOCKER_HUB_USERNAME',
                    passwordVariable: 'DOCKER_HUB_PASSWORD',
                )]) {
                    sh '''
                        if [ -n "${FISSILE_DOCKER_REGISTRY}" ]; then
                            docker login -u "${DOCKER_HUB_USERNAME}" -p "${DOCKER_HUB_PASSWORD}" "${FISSILE_DOCKER_REGISTRY}"
                        fi
                    '''
                }
                sh '''
                    set -e +x
                    source ${PWD}/.envrc
                    set -x
                    unset HCF_PACKAGE_COMPILATION_CACHE

                    make vagrant-prep validate
                '''
            }
        }

        stage('dist') {
            steps {
                sh '''
                    set -e +x
                    source ${PWD}/.envrc
                    set -x
                    unset HCF_PACKAGE_COMPILATION_CACHE
                    rm -f scf-*amd64*.zip
                    make helm bundle-dist
                '''
            }
        }

        stage('deploy') {
            when {
                expression { return params.TEST_SMOKE || params.TEST_BRAIN || params.TEST_CATS }
            }
            steps {
                sh """
                    kubectl delete storageclass hostpath || /bin/true
                    kubectl create -f - <<< '{"kind":"StorageClass","apiVersion":"storage.k8s.io/v1","metadata":{"name":"hostpath"},"provisioner":"kubernetes.io/host-path"}'

                    # Unzip the bundle
                    rm -rf unzipped
                    mkdir unzipped
                    unzip -e scf-*linux-amd64*.zip -d unzipped

                    # This is more informational -- even if it fails, we want to try running things anyway to see how far we get.
                    ./unzipped/kube-ready-state-check.sh || /bin/true

                    mkdir unzipped/certs
                    ./unzipped/cert-generator.sh -d "${domain()}" -n ${jobBaseName()}-${BUILD_NUMBER}-scf -o unzipped/certs

                    helm install unzipped/helm/uaa \
                        --name ${jobBaseName()}-${BUILD_NUMBER}-uaa \
                        --namespace ${jobBaseName()}-${BUILD_NUMBER}-uaa \
                        --set env.CLUSTER_ADMIN_PASSWORD=changeme \
                        --set env.DOMAIN=${domain()} \
                        --set env.UAA_ADMIN_CLIENT_SECRET=uaa-admin-client-secret \
                        --set env.UAA_HOST=uaa.${domain()} \
                        --set env.UAA_PORT=2793 \
                        --set kube.external_ip=${ipAddress()} \
                        --set kube.storage_class.persistent=hostpath \
                        --values unzipped/certs/uaa-cert-values.yaml

                    helm install unzipped/helm/cf \
                        --name ${jobBaseName()}-${BUILD_NUMBER}-scf \
                        --namespace ${jobBaseName()}-${BUILD_NUMBER}-scf \
                        --set env.CLUSTER_ADMIN_PASSWORD=changeme \
                        --set env.DOMAIN=${domain()} \
                        --set env.UAA_ADMIN_CLIENT_SECRET=uaa-admin-client-secret \
                        --set env.UAA_HOST=uaa.${domain()} \
                        --set env.UAA_PORT=2793 \
                        --set kube.external_ip=${ipAddress()} \
                        --set kube.storage_class.persistent=hostpath \
                        --values unzipped/certs/scf-cert-values.yaml

                    echo Waiting for all pods to be ready...
                    set +o xtrace
                    for ns in "${jobBaseName()}-${BUILD_NUMBER}-uaa" "${jobBaseName()}-${BUILD_NUMBER}-scf" ; do
                        while ! ( kubectl get pods -n "\${ns}" | awk '{ if (match(\$2, /^([0-9]+)\\/([0-9]+)\$/, c) && c[1] != c[2]) { print ; exit 1 } }' ) ; do
                            sleep 10
                        done
                    done
                    kubectl get pods --all-namespaces
                """
            }
        }

        stage('smoke') {
            when {
                expression { return params.TEST_SMOKE }
            }
            steps {
                runTest('smoke-tests')
            }
        }

        stage('brain') {
            when {
                expression { return params.TEST_BRAIN }
            }
            steps {
                runTest('acceptance-tests-brain')
            }
        }

        stage('cats') {
            when {
                expression { return params.TEST_CATS }
            }
            steps {
                runTest('acceptance-tests')
            }
        }

        stage('tar_sources') {
          when {
                expression { return params.TAR_SOURCES }
          }
          steps {
                sh '''
                    set -e +x
                    source ${PWD}/.envrc
                    make compile-clean
                '''
          }
        }

        stage('commit_sources') {
          when {
                expression { return params.COMMIT_SOURCES }
          }
          steps {
                withCredentials([usernamePassword(
                    credentialsId: params.OBS_CREDENTIALS,
                    usernameVariable: 'OBS_CREDENTIALS_USERNAME',
                    passwordVariable: 'OBS_CREDENTIALS_PASSWORD',
                )]) {
                sh '''
                  set -e +x
                  source ${PWD}/.envrc
                  echo -e "[general]
apiurl = https://api.opensuse.org
[https://api.opensuse.org]
user = ${OBS_CREDENTIALS_USERNAME}
pass = ${OBS_CREDENTIALS_PASSWORD}
" > ~/.oscrc
                  make osc-commit-sources
                  rm ~/.oscrc
                '''
                }
          }
        }

        stage('publish_docker') {
            when {
                expression { return params.PUBLISH_DOCKER }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: params.DOCKER_CREDENTIALS,
                    usernameVariable: 'DOCKER_HUB_USERNAME',
                    passwordVariable: 'DOCKER_HUB_PASSWORD',
                )]) {
                    sh 'docker login -u "${DOCKER_HUB_USERNAME}" -p "${DOCKER_HUB_PASSWORD}" '
                }
                sh '''
                    set -e +x
                    source ${PWD}/.envrc
                    set -x
                    unset HCF_PACKAGE_COMPILATION_CACHE
                    make publish
                '''
            }
        }

        stage('publish_s3') {
            when {
                expression { return params.PUBLISH_S3 }
            }
            steps {
                withAWS(region: params.S3_REGION) {
                    withCredentials([usernamePassword(
                        credentialsId: params.S3_CREDENTIALS,
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY',
                    )]) {
                        script {
                            def files = findFiles(glob: 'scf-*amd64*.zip')
                            def subdir = "${params.S3_PREFIX}${distSubDir()}"
                            def prefix = distPrefix()

                            for ( int i = 0 ; i < files.size() ; i ++ ) {
                                s3Upload(
                                    file: files[i].path,
                                    bucket: "${params.S3_BUCKET}",
                                    path: "${subdir}${prefix}${files[i].name}",
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            sh """#!/bin/bash
            set -o xtrace
            if kubectl get storageclass hostpath ; then
                kubectl delete storageclass hostpath
            fi
            if kubectl get namespace ${jobBaseName()}-${BUILD_NUMBER}-scf ; then
                kubectl delete namespace ${jobBaseName()}-${BUILD_NUMBER}-scf
            fi
            if kubectl get namespace ${jobBaseName()}-${BUILD_NUMBER}-uaa ; then
                kubectl delete namespace ${jobBaseName()}-${BUILD_NUMBER}-uaa
            fi
            helm list --all --short | grep '${jobBaseName()}-${BUILD_NUMBER}-' | xargs --no-run-if-empty helm delete --purge
            while kubectl get namespace ${jobBaseName()}-${BUILD_NUMBER}-scf ; do
                sleep 1
            done
            while kubectl get namespace ${jobBaseName()}-${BUILD_NUMBER}-uaa ; do
                sleep 1
            done
            """
        }
    }

}
