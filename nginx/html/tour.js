// nginx/html/tour.js
// LabOps Dashboard guided tour — Driver.js v1 wrapper.
// Loaded by index.html just before </body>. Wired to the ? button.

(function () {
  'use strict';

  function dashboardSteps() {
    return [
      {
        popover: {
          title: 'LABOPS DASHBOARD',
          description: 'Your control panel for the Proxmox lab. Provision, connect to, stop, and destroy Windows VMs \u2014 all from this page.',
          showButtons: ['next'],
          nextBtnText: 'Let\u2019s go \u2192'
        }
      },
      {
        element: '#health-badge',
        popover: {
          title: 'SYSTEM HEALTH',
          description: 'Shows the aggregate status of all Docker containers. <strong>ALL SYSTEMS OK</strong> means every container is healthy. If it\u2019s degraded, check the Services panel on the right.',
          side: 'bottom', align: 'end'
        }
      },
      {
        element: '#vm-list',
        popover: {
          title: 'VIRTUAL MACHINES',
          description: 'Live list of all lab VMs (IDs 200\u2013299) pulled from Proxmox every 15 seconds. Each card shows the VM name, status, IP address, and template type.',
          side: 'right', align: 'start'
        }
      },
      {
        element: '#vm-list',
        popover: {
          title: 'START \u2014 CONNECT RDP',
          description: '<strong>Start</strong> boots a stopped VM on Proxmox \u2014 takes 30\u201360 seconds for Windows to finish loading.<br><br>Once running, <strong>Connect RDP</strong> opens a browser-based RDP session via Guacamole. No VPN or RDP client needed.',
          side: 'right', align: 'start'
        }
      },
      {
        element: '#vm-list',
        popover: {
          title: 'STOP A VM',
          description: '<strong>Stop</strong> sends a graceful shutdown to the VM \u2014 equivalent to clicking Shut Down in Windows. The VM stays on Proxmox and can be started again. Use this between demo sessions to save resources.',
          side: 'right', align: 'start'
        }
      },
      {
        element: '#vm-list',
        popover: {
          title: 'DESTROY A VM',
          description: '<strong>Destroy</strong> permanently deletes the VM from Proxmox \u2014 disk and all. This cannot be undone. Use it to reclaim resources after a demo. You\u2019ll always be asked to confirm first.',
          side: 'right', align: 'start'
        }
      },
      {
        element: '.provision-form',
        popover: {
          title: 'PROVISION A NEW VM',
          description: 'Clone a new Windows VM from a Proxmox template. Choose your type:<br><br>\u2022 <strong>Windows 11</strong> \u2014 Sophos Endpoint installed, sandcat pre-deployed<br>\u2022 <strong>Windows 11 (Unmanaged)</strong> \u2014 clean install, no security software<br>\u2022 <strong>Windows Server</strong> \u2014 server OS for specific scenarios<br><br>Provisioning takes 2\u20134 minutes. The new VM will appear in the list automatically.',
          side: 'top', align: 'start'
        }
      },
      {
        element: '#svc-list',
        popover: {
          title: 'DOCKER SERVICES',
          description: 'Shows the health of every container in the LabOps stack \u2014 Nginx, API, Guacamole, guacd, PostgreSQL, and Portainer. If a service is <strong style="color:#ff4444">DOWN</strong>, run <code>make restart</code> on the Mac Mini.',
          side: 'left', align: 'start'
        }
      },
      {
        element: '.links-grid',
        popover: {
          title: 'QUICK LINKS',
          description: '\u2022 <strong>Guacamole</strong> \u2014 The RDP gateway. Open this if a direct Connect RDP fails and you need to troubleshoot the connection.<br>\u2022 <strong>Portainer</strong> \u2014 Docker container management. Restart individual containers here.<br>\u2022 <strong>Proxmox</strong> \u2014 The hypervisor console. Use for anything the dashboard can\u2019t do \u2014 snapshots, hardware config, console access.',
          side: 'left', align: 'start',
          showButtons: ['previous', 'next'],
          nextBtnText: 'Done \u2713'
        }
      }
    ];
  }

  function launchTour() {
    window.driver.js.driver({
      animate: true,
      showProgress: true,
      allowClose: true,
      stagePadding: 6,
      overlayOpacity: 0.3,
      steps: dashboardSteps()
    }).drive();
  }

  window.initTour = function () {
    var helpBtn = document.getElementById('tour-help-btn');
    if (helpBtn) {
      helpBtn.addEventListener('click', launchTour);
    }
  };

}());
