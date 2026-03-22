import { describe, it } from 'node:test'
import assert from 'node:assert/strict'

const { ContainerManager } = await import('../out/container.js')

describe('ContainerManager', () => {
  it('detects available container runtime', () => {
    const cm = new ContainerManager()
    // On this dev machine, podman or docker should be available
    const rt = cm.detectRuntime()
    assert.ok(
      rt === 'podman' || rt === 'docker' || rt === null,
      `runtime should be podman, docker, or null — got: ${rt}`
    )
  })

  it('detectRuntime returns null when no runtime exists', () => {
    const cm = new ContainerManager()
    // Override PATH to simulate missing tools
    const origPath = process.env.PATH
    process.env.PATH = ''
    const rt = cm.detectRuntime()
    process.env.PATH = origPath
    assert.equal(rt, null)
  })

  it('builds correct run command', () => {
    const cm = new ContainerManager({
      image: 'yaccob/pandia:latest',
      port: 3300,
      containerName: 'pandia-test-cmd'
    })
    const cmd = cm.buildRunCommand('podman')
    assert.ok(cmd.includes('podman run'))
    assert.ok(cmd.includes('-p 3300:3300'))
    assert.ok(cmd.includes('yaccob/pandia:latest'))
    assert.ok(cmd.includes('--serve 3300'))
    assert.ok(cmd.includes('--name pandia-test-cmd'))
    assert.ok(cmd.includes('-d'))
    assert.ok(cmd.includes('--rm'))
  })

  it('builds correct stop command', () => {
    const cm = new ContainerManager({
      containerName: 'pandia-test-stop'
    })
    const cmd = cm.buildStopCommand('docker')
    assert.ok(cmd.includes('docker stop pandia-test-stop'))
  })
})
