import { Component, type ErrorInfo, type ReactNode } from 'react'
export default class ErrorBoundary extends Component<{children:ReactNode},{failed:boolean}> {
  state={failed:false}
  static getDerivedStateFromError(){ return {failed:true} }
  componentDidCatch(error:Error, info:ErrorInfo){ console.error('NexusMart UI error', error, info) }
  render(){
    if(this.state.failed) return <main className="loading"><h2>Something went wrong.</h2><p>Please reload NexusMart. Unsaved data was not submitted.</p><button className="primary" onClick={()=>location.reload()}>Reload</button></main>
    return this.props.children
  }
}
