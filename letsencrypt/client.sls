{%- from "letsencrypt/map.jinja" import client with context %}

{%- if client.enabled %}

{%- if client.remote is defined %}

{% for domain_name, domain in client.remote.iteritems() %}

letsencrypt_certificate_dir:
  file.directory:
  - names:
    - /etc/letsencrypt/live/{{ domain.name }}
  - makedirs: true

letsencrypt_certificate_fullchain:
  file.managed:
  - name: /etc/letsencrypt/live/{{ domain.name }}/fullchain.pem
  - source: salt://letsencrypt/files/{{ domain.name }}_fullchain.pem

letsencrypt_certificate_privkey:
  file.managed:
  - name: /etc/letsencrypt/live/{{ domain.name }}/privkey.pem
  - source: salt://letsencrypt/files/{{ domain.name }}_privkey.pem

{%- endfor %}

{%- else %}

letsencrypt-packages:
  pkg.installed:
  - names: {{ client.pkgs }}

letsencrypt-config:
  file.managed:
    - name: /etc/letsencrypt/cli.ini
    - makedirs: true
    - contents_pillar: letsencrypt:client:config

letsencrypt-client-git:
  git.latest:
    - name: https://github.com/letsencrypt/letsencrypt
    - target: {{ client.cli_install_dir }}

/usr/local/bin/check_letsencrypt_cert.sh:
  file.managed:
    - mode: 755
    - contents: |
        #!/bin/bash
        FIRST_CERT=$1

        for DOMAIN in "$@"
        do
            openssl x509 -in /etc/letsencrypt/live/$1/cert.pem -noout -text | grep DNS:${DOMAIN} > /dev/null || exit 1
        done
        CERT=$(date -d "$(openssl x509 -in /etc/letsencrypt/live/$1/cert.pem -enddate -noout | cut -d'=' -f2)" "+%s")
        CURRENT=$(date "+%s")
        REMAINING=$((($CERT - $CURRENT) / 60 / 60 / 24))
        [ "$REMAINING" -gt "30" ] || exit 1
        echo Domains $@ are in cert and cert is valid for $REMAINING days

{% for setname, domainlist in client.domainset.items() %}
create-initial-cert-{{ setname }}-{{ domainlist[0] }}:
  cmd.run:
    - unless: /usr/local/bin/check_letsencrypt_cert.sh {{ domainlist|join(' ') }}
    - name: {{ client.cli_install_dir }}/letsencrypt-auto -d {{ domainlist|join(' -d ') }} certonly
    - require:
      - file: letsencrypt-config

letsencrypt-crontab-{{ setname }}-{{ domainlist[0] }}:
  cron.present:
    - name: /usr/local/bin/check_letsencrypt_cert.sh {{ domainlist|join(' ') }} > /dev/null ||{{
          client.cli_install_dir
        }}/letsencrypt-auto -d {{ domainlist|join(' -d ') }} certonly
    - month: '*'
    - minute: random
    - hour: random
    - dayweek: '*'
    - identifier: letsencrypt-{{ setname }}-{{ domainlist[0] }}
    - require:
      - cmd: create-initial-cert-{{ setname }}-{{ domainlist[0] }}

/etc/letsencrypt/live/{{ domainlist[0] }}/fullchain.pem:
  file.symlink:
    - target: /srv/salt/env/dev/letsencrypt/letsencrypt/files/{{ domainlist[0] }}_fullchain.pem

/etc/letsencrypt/live/{{ domainlist[0] }}/privkey.pem:
  file.symlink:
    - target: /srv/salt/env/dev/letsencrypt/letsencrypt/files/{{ domainlist[0] }}_privkey.pem

{% endfor %}

{%- endif %}

{%- endif %}
